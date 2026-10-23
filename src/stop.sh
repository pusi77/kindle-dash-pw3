#!/bin/sh
# Stop the loop: STOP covers a suspended daemon (checked at next wake-up),
# SIGTERM a running one (trap restores and restarts framework).
DIR=/mnt/us/dashboard
touch "$DIR/STOP"
[ -f "$DIR/dash.pid" ] && kill -TERM "$(cat "$DIR/dash.pid")" 2>/dev/null
