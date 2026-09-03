#!/bin/bash
# peon-poke remote installer — one-liner entry point:
#
#   curl -fsSL https://raw.githubusercontent.com/romeobravo/peon-poke/main/install-remote.sh | bash
#
# Fetches the runtime files + precompiled arm64 binary into a temp dir and
# runs the same install.sh used for source installs. No repo clone needed.
# Override the source with PEON_POKE_BASE (e.g. a fork or file:// for tests).
set -euo pipefail

BASE="${PEON_POKE_BASE:-https://raw.githubusercontent.com/romeobravo/peon-poke/main}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  mkdir -p "$(dirname "$TMP/$2")"
  curl -fsSL "$BASE/$1" -o "$TMP/$2" || { echo "peon-poke: failed to fetch $1" >&2; exit 1; }
}

fetch install.sh                 install.sh
fetch poke.sh                    poke.sh
fetch config.json                config.json
fetch dist/poke-darwin-arm64     dist/poke-darwin-arm64
fetch plugins/pi/poke.ts         plugins/pi/poke.ts
for a in codex gemini grok cursor; do
  fetch "adapters/$a.sh"         "adapters/$a.sh"
done
chmod +x "$TMP/dist/poke-darwin-arm64"

bash "$TMP/install.sh"
