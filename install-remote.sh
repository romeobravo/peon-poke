#!/bin/bash
# peon-poke remote installer — one-liner entry point:
#
#   curl -fsSL https://raw.githubusercontent.com/romeobravo/peon-poke/main/install-remote.sh | bash
#
# Runtime files are pinned to the LATEST GITHUB RELEASE, not main — pushing
# to main never changes what this installs. Only this ~100-line bootstrap
# itself is served from main. Every fetched file is verified against the
# release's SHA256SUMS manifest before anything executes. Pin an explicit
# version instead:
#   PEON_POKE_BASE=https://raw.githubusercontent.com/romeobravo/peon-poke/v0.4.3 bash install-remote.sh
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
  mkdir -p "$(dirname "$TMP/$1")"
  curl -fsSL "$BASE/$1" -o "$TMP/$1" || { echo "peon-poke: failed to fetch $1" >&2; exit 1; }
}

# valid_payload_path <p>: a manifest entry we are willing to fetch.
# Rejects, before a single byte is written, anything that could escape
# $TMP or that we do not expect to ship: absolute paths, backslashes,
# "."/".." components, characters outside a conservative path charset,
# and top-level names outside the known payload set (adding a new
# top-level file means updating this allowlist AND scripts/sha256sums.sh).
valid_payload_path() {
  local p="$1" part
  case "$p" in
    /*|*\\*|""|"."|"..") return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
    install.sh|peon-poke|peon-poke-setup|uninstall.sh|poke.sh|config.json|dist/*|plugins/*|adapters/*) ;;
    *) return 1 ;;
  esac
  local IFS='/'
  for part in $p; do
    case "$part" in "."|".."|"") return 1 ;; esac
  done
  return 0
}

# The manifest is both the file list and the integrity check: everything
# it names is fetched, then verified — but each entry must pass the
# payload-path check first, so a hostile manifest cannot make us write
# outside $TMP (../ traversal) even before anything is executed.
# (Regenerate with scripts/sha256sums.sh.)
fetch SHA256SUMS
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if ! valid_payload_path "$f"; then
    echo "peon-poke: SHA256SUMS lists invalid or unexpected path '$f' — aborting" >&2
    exit 1
  fi
  fetch "$f"
done < <(awk 'NF {print $2}' "$TMP/SHA256SUMS")

SUMS_OUT="$(cd "$TMP" && shasum -a 256 -c SHA256SUMS 2>&1)" || {
  echo "peon-poke: integrity check FAILED — aborting, nothing was executed:" >&2
  printf '%s\n' "$SUMS_OUT" >&2
  exit 1
}
echo "> Integrity verified: $(printf '%s\n' "$SUMS_OUT" | grep -c ': OK$') files (sha256)"

chmod +x "$TMP/dist/poke-darwin-universal" "$TMP/peon-poke" "$TMP/peon-poke-setup" "$TMP/uninstall.sh"
bash "$TMP/install.sh"
