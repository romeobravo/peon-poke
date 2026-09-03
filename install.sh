#!/bin/bash
# peon-poke installer (from a repo clone): builds from source — or falls
# back to the precompiled arm64 binary in dist/ — then runs peon-poke-setup.
#
# Usage: bash install.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- obtain the binary: source build if possible, else precompiled arm64 ---
if [ -f "$REPO_DIR/src/poke.c" ] && command -v clang >/dev/null 2>&1; then
  echo "> Building poke from source..."
  make -C "$REPO_DIR" >/dev/null
elif [ -f "$REPO_DIR/dist/poke-darwin-arm64" ] && [ "$(uname -m)" = "arm64" ]; then
  echo "> Using precompiled arm64 binary..."
  mkdir -p "$REPO_DIR/bin"
  cp "$REPO_DIR/dist/poke-darwin-arm64" "$REPO_DIR/bin/poke"
else
  echo "! no source/clang build and no precompiled binary for $(uname -m)" >&2
  exit 1
fi

exec bash "$REPO_DIR/peon-poke-setup"
