#!/bin/sh
# Start dash.sh fully detached: own session, no inherited fds (the scriptlet launcher
# pipes our stdout to fbink and would otherwise wait on it), own log.
DIR=/mnt/us/dashboard
mkdir -p "$DIR/logs"
# pid file, not pgrep -f: over SSH, pgrep -f also matches the remote shell whose cmdline contains the pattern
if [ -f "$DIR/dash.pid" ] && kill -0 "$(cat "$DIR/dash.pid")" 2>/dev/null; then
  echo "dash.sh already running"
  exit 1
fi
rm -f "$DIR/STOP"
setsid nohup sh "$DIR/dash.sh" </dev/null >>"$DIR/logs/dash.log" 2>&1 &
echo $! >"$DIR/dash.pid"
