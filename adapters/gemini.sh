#!/bin/bash
# peon-boop adapter for Gemini CLI
# Gemini hook events arrive as argv (e.g. adapters/gemini.sh SessionStart).
#
# Setup: point Gemini's lifecycle hooks at this script.
set -euo pipefail

BOOP_SH="${BOOP_DIR:-$HOME/.peon-boop}/boop.sh"
[ -f "$BOOP_SH" ] || exit 0

EVENT="${1:-}"

case "$EVENT" in
  Stop|stop|TurnComplete)             exec bash "$BOOP_SH" task.complete ;;
  Error|error)                        exec bash "$BOOP_SH" task.error ;;
  Notification|notification)          exec bash "$BOOP_SH" input.required ;;
  SessionStart|session_start)         exec bash "$BOOP_SH" session.start ;;
  *)                                  exit 0 ;;
esac
