#!/bin/bash
# peon-poke adapter for Gemini CLI
# Gemini hook events arrive as argv (e.g. adapters/gemini.sh SessionStart).
#
# Setup: point Gemini's lifecycle hooks at this script.
set -euo pipefail

POKE_SH="${POKE_DIR:-$HOME/.peon-poke}/poke.sh"
[ -f "$POKE_SH" ] || exit 0

EVENT="${1:-}"

case "$EVENT" in
  Stop|stop|TurnComplete)             exec bash "$POKE_SH" task.complete ;;
  Error|error)                        exec bash "$POKE_SH" task.error ;;
  Notification|notification)          exec bash "$POKE_SH" input.required ;;
  SessionStart|session_start)         exec bash "$POKE_SH" session.start ;;
  *)                                  exit 0 ;;
esac
