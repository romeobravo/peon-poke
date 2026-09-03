#!/bin/bash
# peon-poke adapter for OpenAI Codex CLI.
#
# Codex invokes the configured `notify` program with ONE argument: a JSON
# object whose "type" field names the event (e.g. "agent-turn-complete").
# Hook-style integrations instead pass a JSON object on stdin with a
# "hook_event_name" field. A very old Codex build passed the bare event
# name as argv — still accepted for safety.
#
# Setup (managed by peon-poke-setup) in ~/.codex/config.toml:
#   notify = ["bash", "<home>/.peon-poke/adapters/codex.sh"]
set -euo pipefail

POKE_SH="${POKE_DIR:-$HOME/.peon-poke}/poke.sh"
[ -f "$POKE_SH" ] || exit 0

# Normalize whatever Codex handed us into a comparison key: JSON argv
# ("type"/"hook_event_name"), JSON on stdin, or a bare legacy event name.
# Case and separators (-/_) are squashed so "SessionStart", "session_start"
# and "session-start" all match.
EVENT="$(python3 -c '
import json, re, sys

def norm(raw):
    try:
        obj = json.loads(raw)
        if isinstance(obj, dict):
            raw = obj.get("type") or obj.get("hook_event_name") or ""
    except Exception:
        pass
    return re.sub(r"[-_]", "", raw.strip().lower())

cand = sys.argv[1] if len(sys.argv) > 1 else ""
if not cand and not sys.stdin.isatty():
    try:
        cand = sys.stdin.read()
    except Exception:
        pass
print(norm(cand) if cand else "")
' "${1:-}" 2>/dev/null || true)"

case "$EVENT" in
  agentturncomplete|stop|turnend)      exec bash "$POKE_SH" task.complete ;;
  error)                               exec bash "$POKE_SH" task.error ;;
  permission|approvalrequired)         exec bash "$POKE_SH" input.required ;;
  sessionstart|sessionconfigured)      exec bash "$POKE_SH" session.start ;;
  *)                                  exit 0 ;;
esac
