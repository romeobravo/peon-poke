#!/bin/bash
# peon-poke adapter for OpenAI Codex CLI
# Handles both the legacy `notify` callback (event name as argv) and the
# stable hook events (JSON on stdin with hook_event_name).
#
# Setup (legacy notify) in ~/.codex/config.toml:
#   notify = ["bash", "<home>/.peon-poke/adapters/codex.sh"]
set -euo pipefail

POKE_SH="${POKE_DIR:-$HOME/.peon-poke}/poke.sh"
[ -f "$POKE_SH" ] || exit 0

EVENT="${1:-}"
if [ -z "$EVENT" ] && [ ! -t 0 ]; then
  EVENT="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("hook_event_name",""))
except Exception: pass' 2>/dev/null || true)"
fi

case "$EVENT" in
  agent-turn-complete|stop|turn_end)   exec bash "$POKE_SH" task.complete ;;
  error)                              exec bash "$POKE_SH" task.error ;;
  permission|approval_required)       exec bash "$POKE_SH" input.required ;;
  session_start)                      exec bash "$POKE_SH" session.start ;;
  *)                                  exit 0 ;;
esac
