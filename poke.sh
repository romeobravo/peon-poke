#!/bin/bash
# peon-poke dispatcher: maps agent events to haptic patterns.
#
# Usage: poke.sh <category>        e.g. poke.sh task.complete
#        poke.sh <pattern>         name or raw gaps, e.g. poke.sh 60,120,40
#
# Categories (same taxonomy as peon-ping):
#   session.start     new agent session began
#   task.acknowledge  agent picked up work
#   task.complete     agent finished, waiting for you
#   task.error        agent errored
#   input.required    agent needs permission/input
#
# Config (~/.config/peon-poke/config.json):
#   categories: which events poke at all
#   patterns:   pattern per category (name or raw gap list)
#   custom:     user-defined names -> gap lists; overrides built-in names
#   strength:   click intensity 1-6 (default 6)
set -uo pipefail

POKE_DIR="${POKE_DIR:-$HOME/.peon-poke}"
POKE_BIN="${POKE_BIN:-$POKE_DIR/bin/poke}"
CONFIG="${POKE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/peon-poke/config.json}"
[ -f "$CONFIG" ] || CONFIG="$POKE_DIR/config.json"

TOKEN="${1:-}"
[ -n "$TOKEN" ] || exit 0
[ -x "$POKE_BIN" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

PATTERN_STRENGTH="$(python3 - "$CONFIG" "$TOKEN" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(1)
token = sys.argv[2]
if not cfg.get("enabled", True):
    sys.exit(1)
custom = cfg.get("custom", {}) or {}

def resolve(pat):
    return custom.get(pat, pat)

if token in cfg.get("categories", {}) or token in cfg.get("patterns", {}):
    # category mode: gated by the categories map
    if not cfg.get("categories", {}).get(token, False):
        sys.exit(1)
    pat = resolve(cfg.get("patterns", {}).get(token, ""))
else:
    # pattern mode: explicit name or raw gap list (bypasses category gating)
    pat = resolve(token)

if not pat:
    sys.exit(1)
print(pat)
print(cfg.get("strength", 6))
PY
)" || exit 0
PATTERN="$(printf '%s\n' "$PATTERN_STRENGTH" | sed -n 1p)"
STRENGTH="$(printf '%s\n' "$PATTERN_STRENGTH" | sed -n 2p)"
[ -n "$PATTERN" ] || exit 0

# Detached + quiet: hooks must never block or spam the host agent.
# "$PATTERN" stays quoted — patterns are single spec strings ("[60, 120, 40]",
# "boop"); unquoted expansion word-splits spaced lists and glob-expands
# stray "*", and bin/poke only reads argv[1] so the rest is silently dropped.
POKE_QUIET=1 POKE_PATTERN="$STRENGTH" "$POKE_BIN" "$PATTERN" >/dev/null 2>&1 &
