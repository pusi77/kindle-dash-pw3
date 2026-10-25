#!/bin/sh
# Fetch a new dashboard image into "$1". System curl verifies TLS (busybox wget doesn't).
# A plain path (no scheme) is copied locally: this curl build has no file:// support.
OUT=$1
case "$DASH_URL" in
/*) exec cp "$DASH_URL" "$OUT" ;;
esac

fetch() {
  curl -sSf --max-time 30 --retry 3 --retry-delay 2 \
    -H "X-Kindle-Battery: $(gasgauge-info -s)" \
    "$@" -o "$OUT" "$DASH_URL"
}

# Optional DASH_TOKEN from env.sh, sent as "Authorization: Bearer". The header goes through stdin
# (curl -H @-), so the token never appears on curl's command line (ps). dash.sh's DEBUG trace
# doesn't reach this script: it runs as a separate process.
if [ -n "$DASH_TOKEN" ]; then
  printf 'Authorization: Bearer %s\n' "$DASH_TOKEN" | fetch -H @-
else
  fetch
fi
