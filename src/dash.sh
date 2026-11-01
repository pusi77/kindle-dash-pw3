#!/bin/sh
# Adapted from pascalw/kindle-dash v1.0.0-beta.4 for Kindle PW3 / FW 5.11.1.1.
# Usage: dash.sh        -> daemon loop (stops framework, suspends via RTC)
#        dash.sh once   -> single fetch + draw, no framework stop, no suspend, Wi-Fi left as is
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

# Trace only after env.sh: its assignments (DASH_TOKEN) must not end up in the log.
DEBUG=${DEBUG:-false}
[ "$DEBUG" = true ] && set -x

INTERVAL_MINUTES=${INTERVAL_MINUTES:-5}
ACTIVE_HOURS=${ACTIVE_HOURS:-*}
minute_field="*/$INTERVAL_MINUTES"
[ "$INTERVAL_MINUTES" -ge 60 ] && minute_field=0
REFRESH_SCHEDULE=${REFRESH_SCHEDULE:-"$minute_field $ACTIVE_HOURS * * *"}
TIMEZONE=${TIMEZONE:-UTC}
FULL_DISPLAY_REFRESH_RATE=${FULL_DISPLAY_REFRESH_RATE:-0}
# A wait longer than one interval means we're outside ACTIVE_HOURS: show sleeping.png instead.
SLEEP_SCREEN_INTERVAL=${SLEEP_SCREEN_INTERVAL:-$((INTERVAL_MINUTES * 60 + 60))}
# Optional: let the server set the schedule (X-Dash-Schedule / X-Dash-Sleep-After response
# headers, see IMAGE-SOURCES.md). The last one received is kept in local/schedule.override.
ALLOW_SERVER_SCHEDULE=${ALLOW_SERVER_SCHEDULE:-false}
SERVER_SCHEDULE_MIN_MINUTES=${SERVER_SCHEDULE_MIN_MINUTES:-5}
SCHEDULE_OVERRIDE="$DIR/local/schedule.override"
ENV_REFRESH_SCHEDULE=$REFRESH_SCHEDULE
ENV_SLEEP_SCREEN_INTERVAL=$SLEEP_SCREEN_INTERVAL
if [ "$ALLOW_SERVER_SCHEDULE" = true ] && [ -f "$SCHEDULE_OVERRIDE" ]; then
  # shellcheck source=/dev/null  # written by apply_server_schedule, validated before writing
  . "$SCHEDULE_OVERRIDE"
fi
# fetch-dashboard.sh runs as a child process: export the schedule so it can send it to the server.
export REFRESH_SCHEDULE TIMEZONE SLEEP_SCREEN_INTERVAL
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

# Value of a response header saved by curl -D (last one wins, e.g. after redirects).
header_value() {
  grep -i "^$2:" "$1" 2>/dev/null | tail -n 1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//;s/ *$//'
}

# Minute field accepted from a server: "*/N" with N >= SERVER_SCHEDULE_MIN_MINUTES, or a list of
# at most 60/SERVER_SCHEDULE_MIN_MINUTES plain minutes. Anything denser could drain the battery.
minute_field_ok() {
  case $1 in
  "*/"*)
    n=${1#"*/"}
    case $n in '' | *[!0-9]*) return 1 ;; esac
    [ "$n" -ge "$SERVER_SCHEDULE_MIN_MINUTES" ]
    ;;
  '' | *[!0-9,]*) return 1 ;;
  *)
    [ "$(echo "$1" | tr ',' '\n' | grep -c .)" -le $((60 / SERVER_SCHEDULE_MIN_MINUTES)) ]
    ;;
  esac
}

# Take the schedule from the server's X-Dash-Schedule / X-Dash-Sleep-After response headers, if
# ALLOW_SERVER_SCHEDULE=true. "X-Dash-Schedule: default" goes back to env.sh. Invalid values are
# logged and ignored. Applies from the next sleep (main_loop recomputes the wake-up after this).
apply_server_schedule() {
  headers=$1
  [ "$ALLOW_SERVER_SCHEDULE" = true ] && [ -f "$headers" ] || return 0
  schedule=$(header_value "$headers" X-Dash-Schedule)
  [ -n "$schedule" ] || return 0
  if [ "$schedule" = default ]; then
    [ -f "$SCHEDULE_OVERRIDE" ] || return 0
    rm -f "$SCHEDULE_OVERRIDE"
    REFRESH_SCHEDULE=$ENV_REFRESH_SCHEDULE
    SLEEP_SCREEN_INTERVAL=$ENV_SLEEP_SCREEN_INTERVAL
    log "Server schedule removed, back to env.sh: '$REFRESH_SCHEDULE'"
    return 0
  fi
  sleep_after=$(header_value "$headers" X-Dash-Sleep-After)
  [ "$schedule" = "$REFRESH_SCHEDULE" ] && [ "$sleep_after" = "$SLEEP_SCREEN_INTERVAL" ] && return 0

  # Strict whitelist: the values end up in a file that is sourced.
  case $schedule in
  *[!0-9A-Za-z*/,\ -]*)
    log "Ignoring server schedule: invalid characters"
    return 0
    ;;
  esac
  case $sleep_after in
  '' | *[!0-9]*)
    log "Ignoring server schedule '$schedule': X-Dash-Sleep-After must be a number"
    return 0
    ;;
  esac
  if [ "$sleep_after" -lt 60 ]; then
    log "Ignoring server schedule '$schedule': X-Dash-Sleep-After below 60 s"
    return 0
  fi
  if [ "$(echo "$schedule" | awk '{print NF}')" -ne 5 ]; then
    log "Ignoring server schedule '$schedule': expected 5 fields"
    return 0
  fi
  if ! minute_field_ok "$(echo "$schedule" | awk '{print $1}')"; then
    log "Ignoring server schedule '$schedule': more often than every $SERVER_SCHEDULE_MIN_MINUTES min"
    return 0
  fi
  s=$("$DIR/next-wakeup" --schedule="$schedule" --timezone="$TIMEZONE" 2>/dev/null)
  case $s in
  '' | *[!0-9]*)
    log "Ignoring server schedule '$schedule': not a valid cron schedule"
    return 0
    ;;
  esac

  printf "REFRESH_SCHEDULE='%s'\nSLEEP_SCREEN_INTERVAL=%s\n" "$schedule" "$sleep_after" \
    >"$SCHEDULE_OVERRIDE.tmp" && mv "$SCHEDULE_OVERRIDE.tmp" "$SCHEDULE_OVERRIDE"
  REFRESH_SCHEDULE=$schedule
  SLEEP_SCREEN_INTERVAL=$sleep_after
  log "Server schedule applied: '$REFRESH_SCHEDULE', sleep screen after ${SLEEP_SCREEN_INTERVAL}s"
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
    rm -f "$DASH_PNG.tmp.headers"
    log "Not updating screen, fetch-dashboard returned $fetch_status"
    return 1
  fi
  apply_server_schedule "$DASH_PNG.tmp.headers"
  rm -f "$DASH_PNG.tmp.headers"
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
