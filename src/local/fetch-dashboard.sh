#!/bin/sh
# Fetch a new dashboard image into "$1". System curl verifies TLS (busybox wget doesn't).
# A plain path (no scheme) is copied locally: this curl build has no file:// support.
case "$DASH_URL" in
/*) exec cp "$DASH_URL" "$1" ;;
esac
curl -sSf --max-time 30 --retry 3 --retry-delay 2 \
  -H "X-Kindle-Battery: $(gasgauge-info -s)" \
  -o "$1" "$DASH_URL"
