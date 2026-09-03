#!/bin/bash
# peon-poke adapter for Cursor IDE
#
# Cursor has NO notification/permission hook — the usable events are
# stop, beforeSubmitPrompt, beforeShellExecution, beforeMCPExecution,
# afterFileEdit, beforeReadFile (same set peon-ping's adapter targets).
# Only stop (task complete) is worth wiring by default; the per-file /
# per-tool events are too noisy.
#
# Setup in ~/.cursor/hooks.json (array format):
#   { "hooks": [
#       { "event": "stop", "command": "bash ~/.peon-poke/adapters/cursor.sh stop", "timeout": 5 }
#   ] }
#
# or dict format:
#   { "hooks": {
#       "stop": [ { "command": "bash ~/.peon-poke/adapters/cursor.sh stop", "timeout": 5 } ]
#   } }
#
# Optional (agent picked up your prompt; enable task.acknowledge in config):
#   { "event": "beforeSubmitPrompt", "command": "bash ~/.peon-poke/adapters/cursor.sh beforeSubmitPrompt" }
set -euo pipefail

POKE_SH="${POKE_DIR:-$HOME/.peon-poke}/poke.sh"
[ -f "$POKE_SH" ] || exit 0

EVENT="${1:-}"

case "$EVENT" in
  stop)                               exec bash "$POKE_SH" task.complete ;;
  beforeSubmitPrompt|beforeShellExecution)
                                      exec bash "$POKE_SH" task.acknowledge ;;
  beforeReadFile|beforeMCPExecution|afterFileEdit)
                                      exit 0 ;;            # too noisy
  *)                                  exit 0 ;;             # unknown: stay silent
esac
