#!/bin/bash
# peon-boop dispatcher: maps agent event categories to haptic patterns.
#
# Usage: boop.sh <category>
#
# Categories (same taxonomy as peon-ping):
#   session.start     new agent session began
#   task.acknowledge  agent picked up work
#   task.complete     agent finished, waiting for you
#   task.error        agent errored
#   input.required    agent needs permission/input
#
# Patterns are configured in config.json (see repo config.json).
set -uo pipefail

BOOP_DIR="${BOOP_DIR:-$HOME/.peon-boop}"
BOOP_BIN="${BOOP_BIN:-$BOOP_DIR/bin/boop}"
CONFIG="${BOOP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/peon-boop/config.json}"
[ -f "$CONFIG" ] || CONFIG="$BOOP_DIR/config.json"

CATEGORY="${1:-}"
[ -n "$CATEGORY" ] || exit 0
[ -x "$BOOP_BIN" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

PATTERN="$(python3 - "$CONFIG" "$CATEGORY" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(1)
cat = sys.argv[2]
if not cfg.get("enabled", True):
    sys.exit(1)
if not cfg.get("categories", {}).get(cat, False):
    sys.exit(1)
print(cfg.get("patterns", {}).get(cat, ""))
PY
)" || exit 0
[ -n "$PATTERN" ] || exit 0

# Detached + quiet: hooks must never block or spam the host agent.
# shellcheck disable=SC2086
BOOP_QUIET=1 "$BOOP_BIN" $PATTERN >/dev/null 2>&1 &
