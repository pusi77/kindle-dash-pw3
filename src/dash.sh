#!/bin/sh
# Adapted from pascalw/kindle-dash v1.0.0-beta.4 for Kindle PW3 / FW 5.11.1.1.
# Usage: dash.sh        -> daemon loop (stops framework, suspends via RTC)
#        dash.sh once   -> single fetch + draw, no framework stop, no suspend, Wi-Fi left as is
DEBUG=${DEBUG:-false}
[ "$DEBUG" = true ] && set -x

DIR="$(cd "$(dirname "$0")" && pwd)"
DASH_PNG="$DIR/dash.png"
FETCH_DASHBOARD_CMD="$DIR/local/fetch-dashboard.sh"
STOP_FILE="$DIR/STOP"
BATTERY_LOG="$DIR/battery.log"

# set -a: export everything env.sh sets (fetch-dashboard.sh is a child process and needs DASH_URL)
set -a
# shellcheck source=/dev/null  # user config, path only known at runtime
[ -f "$DIR/local/env.sh" ] && . "$DIR/local/env.sh"
set +a

INTERVAL_MINUTES=${INTERVAL_MINUTES:-5}
ACTIVE_HOURS=${ACTIVE_HOURS:-*}
minute_field="*/$INTERVAL_MINUTES"
[ "$INTERVAL_MINUTES" -ge 60 ] && minute_field=0
REFRESH_SCHEDULE=${REFRESH_SCHEDULE:-"$minute_field $ACTIVE_HOURS * * *"}
TIMEZONE=${TIMEZONE:-UTC}
FULL_DISPLAY_REFRESH_RATE=${FULL_DISPLAY_REFRESH_RATE:-0}
# A wait longer than one interval means we're outside ACTIVE_HOURS: show sleeping.png instead.
SLEEP_SCREEN_INTERVAL=${SLEEP_SCREEN_INTERVAL:-$((INTERVAL_MINUTES * 60 + 60))}
WIFI_TIMEOUT=${WIFI_TIMEOUT:-30}
# PW3: /sys/devices/platform/mxc_rtc.0 doesn't exist; max77696 RTC channel 1 (rtc0 left to powerd)
RTC=${RTC:-/sys/class/rtc/rtc1/wakealarm}
GOVERNOR=/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# flIntensity 0 still leaves the LED at raw 1/4095; only the driver goes to a true 0.
BACKLIGHT=/sys/class/backlight/max77696-bl/brightness

num_refresh=0

log() { echo "$(date -u '+%F %T') $*"; }

init() {
  log "Starting dashboard with '$REFRESH_SCHEDULE' ($TIMEZONE) refresh..."

  old_fl=$(lipc-get-prop com.lab126.powerd flIntensity)
  old_gov=$(cat "$GOVERNOR" 2>/dev/null)

  trap restore_and_exit INT TERM HUP

  stop framework
  initctl stop webreader >/dev/null 2>&1
  [ -n "$old_gov" ] && echo powersave >"$GOVERNOR"
  lipc-set-prop com.lab126.powerd preventScreenSaver 1
  lights_off
}

lights_off() {
  lipc-set-prop com.lab126.powerd flIntensity 0
  echo 0 >"$BACKLIGHT"
}

# Undo everything init() did and give the device back to the normal UI.
restore_and_exit() {
  log "Shutting down, restarting framework"
  echo 0 >"$RTC" 2>/dev/null
  [ -n "$old_gov" ] && echo "$old_gov" >"$GOVERNOR"
  lipc-set-prop com.lab126.cmd wirelessEnable 1
  lipc-set-prop com.lab126.powerd preventScreenSaver 0
  [ -n "$old_fl" ] && lipc-set-prop com.lab126.powerd flIntensity "$old_fl"
  start framework
  exit 0
}

# Charging or on USB: stay awake (sleep instead of suspend). See notes: isCharging reads 0 at 100% on USB.
on_power() {
  [ "$(lipc-get-prop com.lab126.powerd isCharging)" = 1 ] && return 0
  lipc-get-prop com.lab126.powerd battStateInfo | grep -q '"usb":true'
}

wifi_on() {
  lipc-set-prop com.lab126.cmd wirelessEnable 1
  i=0
  while [ "$(lipc-get-prop com.lab126.wifid cmState)" != CONNECTED ]; do
    [ "$i" -ge "$WIFI_TIMEOUT" ] && log "Couldn't connect to Wi-Fi" && return 1
    i=$((i + 1))
    sleep 1
  done
}

wifi_off() {
  lipc-set-prop com.lab126.cmd wirelessEnable 0
}

prepare_sleep() {
  log "Preparing sleep"
  /usr/sbin/eips -f -g "$DIR/sleeping.png"
  # Give screen time to refresh
  sleep 2
  # Ensure a full screen refresh is triggered after wake from sleep
  num_refresh=$FULL_DISPLAY_REFRESH_RATE
}

# Wi-Fi on, fetch, draw. Wi-Fi is left on: the caller turns it off after the abort window.
refresh_dashboard() {
  log "Refreshing dashboard"
  wifi_t0=$(date +%s)
  fetch_status=1
  if wifi_on; then
    "$FETCH_DASHBOARD_CMD" "$DASH_PNG.tmp"
    fetch_status=$?
  fi

  if [ "$fetch_status" -ne 0 ]; then
    log "Not updating screen, fetch-dashboard returned $fetch_status"
    return 1
  fi
  mv "$DASH_PNG.tmp" "$DASH_PNG"

  if [ "$num_refresh" -eq "$FULL_DISPLAY_REFRESH_RATE" ]; then
    num_refresh=0
    log "Full screen refresh"
    /usr/sbin/eips -f -g "$DASH_PNG"
  else
    log "Partial screen refresh"
    /usr/sbin/eips -g "$DASH_PNG"
  fi

  num_refresh=$((num_refresh + 1))
}

# One line per refresh in battery.log: timestamp, battery %, fetch result, seconds Wi-Fi was on.
log_cycle() {
  result=ok
  [ "$fetch_status" -ne 0 ] && result="fail($fetch_status)"
  echo "$(date -u '+%FT%TZ') batt=$(gasgauge-info -s) fetch=$result wifi_s=$(($(date +%s) - wifi_t0))" >>"$BATTERY_LOG"
}

# Seconds until the next scheduled refresh. Falls back to 300 on garbage: an arithmetic error
# would kill the loop with the framework stopped.
next_wakeup() {
  s=$("$DIR/next-wakeup" --schedule="$REFRESH_SCHEDULE" --timezone="$TIMEZONE")
  case $s in
  '' | *[!0-9]*)
    echo "next-wakeup returned '$s', using 300s" >&2
    s=300
    ;;
  esac
  echo "$s"
}

rtc_sleep() {
  duration=$1

  # < 15s: the alarm could already be in the past when "mem" lands, and never fire.
  if [ "$DEBUG" = true ] || [ "$duration" -lt 15 ] || on_power; then
    log "Sleeping ${duration}s instead of suspending (on power, short interval or DEBUG)"
    sleep "$duration"
    return
  fi

  # wakealarm takes an absolute epoch, reads empty when unset, and is EBUSY if already set.
  echo 0 >"$RTC"
  echo $(($(date +%s) + duration)) >"$RTC"
  if [ -z "$(cat "$RTC")" ]; then
    # Never suspend without a wake alarm: the device would stay asleep until the power button.
    log "RTC alarm not set, sleeping instead of suspending"
    sleep "$duration"
    return
  fi
  echo mem >/sys/power/state
}

main_loop() {
  while true; do
    if [ -f "$STOP_FILE" ]; then
      log "STOP file found"
      restore_and_exit
    fi

    # powerd may re-apply its own level on resume
    lights_off
    log "Battery level: $(gasgauge-info -s)%."

    refreshed=false
    if [ "$(next_wakeup)" -gt "$SLEEP_SCREEN_INTERVAL" ]; then
      action="sleep"
      prepare_sleep
    else
      action="suspend"
      refresh_dashboard
      refreshed=true
    fi

    # Abort window, Wi-Fi still on so STOP can be created over SSH.
    sleep 10
    [ -f "$STOP_FILE" ] && continue

    # On power, battery doesn't matter: keep Wi-Fi up so the device stays reachable.
    on_power || wifi_off
    [ "$refreshed" = true ] && log_cycle

    # recompute: fetch + the 10s pause ate into the interval
    next_wakeup_secs=$(next_wakeup)
    log "Going to $action, next wakeup in ${next_wakeup_secs}s"

    rtc_sleep "$next_wakeup_secs"
  done
}

if [ "$1" = once ]; then
  num_refresh=$FULL_DISPLAY_REFRESH_RATE
  refresh_dashboard
  log_cycle
  exit "$fetch_status"
fi

init
main_loop
