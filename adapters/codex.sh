#!/bin/bash
# peon-boop adapter for OpenAI Codex CLI
# Handles both the legacy `notify` callback (event name as argv) and the
# stable hook events (JSON on stdin with hook_event_name).
#
# Setup (legacy notify) in ~/.codex/config.toml:
#   notify = ["bash", "<home>/.peon-boop/adapters/codex.sh"]
set -euo pipefail

BOOP_SH="${BOOP_DIR:-$HOME/.peon-boop}/boop.sh"
[ -f "$BOOP_SH" ] || exit 0

EVENT="${1:-}"
if [ -z "$EVENT" ] && [ ! -t 0 ]; then
  EVENT="$(python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("hook_event_name",""))
except Exception: pass' 2>/dev/null || true)"
fi

case "$EVENT" in
  agent-turn-complete|stop|turn_end)   exec bash "$BOOP_SH" task.complete ;;
  error)                              exec bash "$BOOP_SH" task.error ;;
  permission|approval_required)       exec bash "$BOOP_SH" input.required ;;
  session_start)                      exec bash "$BOOP_SH" session.start ;;
  *)                                  exit 0 ;;
esac
