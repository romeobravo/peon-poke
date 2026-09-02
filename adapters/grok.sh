#!/bin/bash
# peon-boop adapter for Grok Build
# Grok sends camelCase stdin JSON (hookEventName) with snake_case event
# values (session_start, stop, notification).
#
# Setup: ~/.grok/hooks/peon-boop.json (see README).
set -euo pipefail

BOOP_SH="${BOOP_DIR:-$HOME/.peon-boop}/boop.sh"
[ -f "$BOOP_SH" ] || exit 0

EVENT=""
if [ ! -t 0 ]; then
  EVENT="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("hookEventName",""))
except Exception: pass' 2>/dev/null || true)"
fi

case "$EVENT" in
  stop)                               exec bash "$BOOP_SH" task.complete ;;
  error)                              exec bash "$BOOP_SH" task.error ;;
  notification)                       exec bash "$BOOP_SH" input.required ;;
  session_start)                      exec bash "$BOOP_SH" session.start ;;
  *)                                  exit 0 ;;
esac
