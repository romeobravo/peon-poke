#!/bin/bash
# peon-poke installer (from a repo clone): builds from source — or falls
# back to the precompiled universal binary (macOS 12+, arm64 + x86_64) in
# dist/ — then runs `peon-poke setup`.
#
# Usage: bash install.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- obtain the binary: source build if possible, else precompiled ---
if [ -f "$REPO_DIR/src/poke.c" ] && command -v clang >/dev/null 2>&1; then
  echo "> Building poke from source..."
  make -C "$REPO_DIR" >/dev/null
elif [ -f "$REPO_DIR/dist/poke-darwin-universal" ] \
     && lipo -info "$REPO_DIR/dist/poke-darwin-universal" 2>/dev/null | grep -q "$(uname -m)"; then
  echo "> Using precompiled universal binary (macOS 12+, arm64 + x86_64)..."
  mkdir -p "$REPO_DIR/bin"
  cp "$REPO_DIR/dist/poke-darwin-universal" "$REPO_DIR/bin/poke"
else
  echo "! no source/clang build and no precompiled binary for $(uname -m)" >&2
  exit 1
fi

exec "$REPO_DIR/peon-poke" setup
