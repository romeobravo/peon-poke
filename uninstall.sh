#!/bin/bash
# peon-poke uninstaller: removes hook registrations and installed files.
set -euo pipefail

INSTALL_DIR="${POKE_DIR:-$HOME/.peon-poke}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/peon-poke"

info() { printf "> %s\n" "$*"; }

# Claude Code: drop our hook entries
if [ -f "$HOME/.claude/settings.json" ] && command -v python3 >/dev/null; then
  python3 - <<'PY' && info "Claude Code hooks removed"
import json, os
path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception:
    raise SystemExit(1)
hooks = cfg.get("hooks", {})
for event, entries in list(hooks.items()):
    kept = [e for e in entries if "peon-poke" not in json.dumps(e)]
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
fi

# Codex: remove managed notify block
CODEX_TOML="$HOME/.codex/config.toml"
if [ -f "$CODEX_TOML" ] && grep -q "peon-poke" "$CODEX_TOML"; then
  python3 - "$CODEX_TOML" <<'PY' && info "Codex notify removed"
import sys
path = sys.argv[1]
lines = open(path).readlines()
out, skip_next = [], False
for line in lines:
    if "peon-poke" in line and line.strip().startswith("#"):
        skip_next = True
        continue
    if skip_next:
        skip_next = False
        continue
    if "peon-poke" in line:
        continue
    out.append(line)
open(path, "w").writelines(out)
PY
fi

# pi / omp extensions
for f in "$HOME/.pi/agent/extensions/peon-poke.ts" "$HOME/.omp/agent/extensions/peon-poke.ts"; do
  [ -f "$f" ] && rm -f "$f" && info "Removed $f"
done

# installed files (config kept unless --purge)
rm -rf "$INSTALL_DIR" && info "Removed $INSTALL_DIR"
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$CONFIG_DIR" && info "Removed $CONFIG_DIR"
else
  info "Kept $CONFIG_DIR/config.json (use --purge to remove)"
fi
