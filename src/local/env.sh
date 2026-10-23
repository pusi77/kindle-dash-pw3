#!/bin/sh
# shellcheck disable=SC2034  # variables are used by dash.sh, which sources this file
# Dashboard settings. Plain KEY=value, sourced by dash.sh (no jq/python on the device for JSON).
# Edit over SSH or via USB, takes effect at the next "Start Dashboard".

# https URL, or a local path for offline testing (Wi-Fi still cycles, so battery stats stay realistic)
DASH_URL="/mnt/us/dashboard/test.png"

# Refresh every N minutes. Must divide 60 (1,2,3,4,5,6,10,12,15,20,30) or be 60 (on the hour).
INTERVAL_MINUTES=15

# Hours (local time, 0-23, cron syntax) when the dashboard refreshes. Outside them it shows
# sleeping.png and suspends in one go until the next active hour.
# "7-22" = refreshes from 07:00 to 22:45. Wrapping past midnight: "0-1,7-23".
ACTIVE_HOURS="7-22"

# Timezone for ACTIVE_HOURS (the device clock itself stays UTC).
TIMEZONE="Europe/Rome"

# Advanced: a full cron expression overrides INTERVAL_MINUTES/ACTIVE_HOURS, e.g. "*/30 7-22 * * MON-FRI".
#REFRESH_SCHEDULE="*/15 7-22 * * *"

# Partial refreshes ghost over time; full (flashing) refresh every N updates.
FULL_DISPLAY_REFRESH_RATE=4
