#!/bin/bash
# peon-poke remote installer — one-liner entry point:
#
#   curl -fsSL https://raw.githubusercontent.com/romeobravo/peon-poke/main/install-remote.sh | bash
#
# Runtime files are pinned to the LATEST GITHUB RELEASE, not main — pushing
# to main never changes what this installs. Only this ~100-line bootstrap
# itself is served from main. Pin an explicit version instead:
#   PEON_POKE_BASE=https://raw.githubusercontent.com/romeobravo/peon-poke/v0.4.2 bash install-remote.sh
set -euo pipefail

REPO="romeobravo/peon-poke"

if [ -n "${PEON_POKE_BASE:-}" ]; then
  BASE="$PEON_POKE_BASE"
else
  TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null || true)"
  [ -n "$TAG" ] || { echo "peon-poke: could not resolve latest release for $REPO" >&2; exit 1; }
  BASE="https://raw.githubusercontent.com/$REPO/$TAG"
fi
echo "> Installing peon-poke from $BASE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  mkdir -p "$(dirname "$TMP/$2")"
  curl -fsSL "$BASE/$1" -o "$TMP/$2" || { echo "peon-poke: failed to fetch $1" >&2; exit 1; }
}

fetch install.sh                 install.sh
fetch peon-poke-setup            peon-poke-setup
fetch poke.sh                    poke.sh
fetch config.json                config.json
fetch dist/poke-darwin-arm64     dist/poke-darwin-arm64
fetch plugins/pi/poke.ts         plugins/pi/poke.ts
for a in codex gemini grok cursor; do
  fetch "adapters/$a.sh"         "adapters/$a.sh"
done
chmod +x "$TMP/dist/poke-darwin-arm64" "$TMP/peon-poke-setup"

bash "$TMP/install.sh"
