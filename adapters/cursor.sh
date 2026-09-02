#!/bin/bash
# peon-boop adapter for Cursor IDE
# Setup in ~/.cursor/hooks.json:
#   { "hooks": [
#       { "event": "stop",         "command": "bash <home>/.peon-boop/adapters/cursor.sh stop" },
#       { "event": "notification", "command": "bash <home>/.peon-boop/adapters/cursor.sh notification" }
#   ] }
set -euo pipefail

BOOP_SH="${BOOP_DIR:-$HOME/.peon-boop}/boop.sh"
[ -f "$BOOP_SH" ] || exit 0

EVENT="${1:-}"

case "$EVENT" in
  stop)                               exec bash "$BOOP_SH" task.complete ;;
  error)                              exec bash "$BOOP_SH" task.error ;;
  notification)                       exec bash "$BOOP_SH" input.required ;;
  session_start)                      exec bash "$BOOP_SH" session.start ;;
  *)                                  exit 0 ;;
esac
