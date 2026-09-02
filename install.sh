#!/bin/bash
# peon-boop installer: builds the binary, installs to ~/.peon-boop,
# copies config, and registers hooks for detected coding agents.
#
# Usage: bash install.sh [--uninstall-targets]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${BOOP_DIR:-$HOME/.peon-boop}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/peon-boop"

BOLD=$'\033[1m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RESET=$'\033[0m'
info() { printf "%s>%s %s\n" "$GREEN" "$RESET" "$*"; }
warn() { printf "%s!%s %s\n" "$YELLOW" "$RESET" "$*"; }

command -v clang >/dev/null 2>&1 || { warn "clang not found — cannot build boop"; exit 1; }

# --- build + install files ---
info "Building boop..."
make -C "$REPO_DIR" >/dev/null

info "Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/adapters" "$INSTALL_DIR/plugins/pi"
cp "$REPO_DIR/bin/boop"        "$INSTALL_DIR/bin/boop"
cp "$REPO_DIR/boop.sh"         "$INSTALL_DIR/boop.sh"
cp "$REPO_DIR/adapters/"*.sh   "$INSTALL_DIR/adapters/"
cp "$REPO_DIR/plugins/pi/boop.ts" "$INSTALL_DIR/plugins/pi/boop.ts"
chmod +x "$INSTALL_DIR/bin/boop" "$INSTALL_DIR/boop.sh" "$INSTALL_DIR/adapters/"*.sh

# --- config (never overwrite an existing one) ---
if [ ! -f "$CONFIG_DIR/config.json" ]; then
  mkdir -p "$CONFIG_DIR"
  cp "$REPO_DIR/config.json" "$CONFIG_DIR/config.json"
  info "Config written to $CONFIG_DIR/config.json"
else
  info "Config already present at $CONFIG_DIR/config.json (kept)"
fi

# --- register Claude Code hooks ---
if [ -d "$HOME/.claude" ]; then
  python3 - "$INSTALL_DIR" <<'PY'
import json, os, sys
install_dir = sys.argv[1]
path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception:
    cfg = {}
hooks = cfg.setdefault("hooks", {})
def add(event, category):
    entries = hooks.setdefault(event, [])
    if any("peon-boop" in json.dumps(e) for e in entries):
        return
    entries.append({"matcher": "", "hooks": [{"type": "command",
        "command": f"bash {install_dir}/boop.sh {category}"}]})
add("Stop", "task.complete")
add("Notification", "input.required")
add("SessionStart", "session.start")
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
print("registered")
PY
  info "Claude Code hooks registered (Stop, Notification, SessionStart)"
else
  info "Claude Code not detected (~/.claude) — skipping"
fi

# --- register Codex notify ---
if [ -d "$HOME/.codex" ]; then
  CODEX_TOML="$HOME/.codex/config.toml"
  if ! grep -q "peon-boop" "$CODEX_TOML" 2>/dev/null; then
    printf '\n# peon-boop (managed — remove to uninstall)\nnotify = ["bash", "%s/adapters/codex.sh"]\n' \
      "$INSTALL_DIR" >> "$CODEX_TOML"
    info "Codex notify registered in ~/.codex/config.toml"
  else
    info "Codex notify already registered"
  fi
else
  info "Codex not detected (~/.codex) — skipping"
fi

# --- install pi / oh-my-pi extension ---
for ext_dir in "$HOME/.pi/agent/extensions" "$HOME/.omp/agent/extensions"; do
  if [ -d "$ext_dir" ]; then
    cp "$INSTALL_DIR/plugins/pi/boop.ts" "$ext_dir/peon-boop.ts"
    info "Extension installed: $ext_dir/peon-boop.ts"
  else
    info "$(basename "$(dirname "$(dirname "$ext_dir")")") not detected ($ext_dir) — skipping"
  fi
done

echo
info "${BOLD}peon-boop installed.${RESET} Patterns live in $CONFIG_DIR/config.json"
echo "  Manual adapters: gemini, grok, cursor — see README.md"
echo "  Test: $INSTALL_DIR/bin/boop"        # default pattern: chirp
