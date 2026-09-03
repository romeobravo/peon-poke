#!/bin/bash
# peon-poke adapter for Grok Build
# Grok sends camelCase stdin JSON (hookEventName) with snake_case event
# values (session_start, stop, notification).
#
# Setup: ~/.grok/hooks/peon-poke.json (see README).
set -euo pipefail

POKE_SH="${POKE_DIR:-$HOME/.peon-poke}/poke.sh"
[ -f "$POKE_SH" ] || exit 0

EVENT=""
if [ ! -t 0 ]; then
  EVENT="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("hookEventName",""))
except Exception: pass' 2>/dev/null || true)"
fi

case "$EVENT" in
  stop)                               exec bash "$POKE_SH" task.complete ;;
  error)                              exec bash "$POKE_SH" task.error ;;
  notification)                       exec bash "$POKE_SH" input.required ;;
  session_start)                      exec bash "$POKE_SH" session.start ;;
  *)                                  exit 0 ;;
esac
