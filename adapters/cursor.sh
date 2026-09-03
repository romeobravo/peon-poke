#!/bin/bash
# peon-poke adapter for Cursor IDE
# Setup in ~/.cursor/hooks.json:
#   { "hooks": [
#       { "event": "stop",         "command": "bash <home>/.peon-poke/adapters/cursor.sh stop" },
#       { "event": "notification", "command": "bash <home>/.peon-poke/adapters/cursor.sh notification" }
#   ] }
set -euo pipefail

POKE_SH="${POKE_DIR:-$HOME/.peon-poke}/poke.sh"
[ -f "$POKE_SH" ] || exit 0

EVENT="${1:-}"

case "$EVENT" in
  stop)                               exec bash "$POKE_SH" task.complete ;;
  error)                              exec bash "$POKE_SH" task.error ;;
  notification)                       exec bash "$POKE_SH" input.required ;;
  session_start)                      exec bash "$POKE_SH" session.start ;;
  *)                                  exit 0 ;;
esac
