#!/bin/bash
# brew-bump.sh — point the Homebrew tap formula at a released peon-poke version.
#
# Usage: scripts/brew-bump.sh [version]      (default: VERSION file contents)
#
# Prereq: the GitHub release exists (gh release create vX.Y.Z ...).
# Flow:   fetch tag tarball -> sha256 -> update url/sha256 in the tap's
#         Formula/peon-poke.rb -> commit + push the tap.
#
# Tap checkout: uses $TAP_DIR if set (or ~/work/homebrew-tap if present),
# otherwise shallow-clones romeobravo/homebrew-tap to a temp dir.
set -euo pipefail

REPO="romeobravo/peon-poke"
TAP_REPO="romeobravo/homebrew-tap"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="${1:-$(cat "$HERE/VERSION")}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
TARBALL="https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"

gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 || {
  echo "brew-bump: release $TAG does not exist on $REPO — create it first" >&2
  exit 1
}

SHA="$(curl -fsSL "$TARBALL" | shasum -a 256 | cut -d' ' -f1)"
echo "==> $TARBALL"
echo "==> sha256 $SHA"

TAP_DIR="${TAP_DIR:-$HOME/work/homebrew-tap}"
TMP_CLONE=""
if [ ! -d "$TAP_DIR/.git" ]; then
  TMP_CLONE="$(mktemp -d)/homebrew-tap"
  git clone -q "https://github.com/$TAP_REPO.git" "$TMP_CLONE"
  TAP_DIR="$TMP_CLONE"
fi

F="$TAP_DIR/Formula/peon-poke.rb"
[ -f "$F" ] || { echo "brew-bump: formula not found at $F" >&2; exit 1; }

python3 - "$F" "$TARBALL" "$SHA" <<'PY'
import re, sys
path, url, sha = sys.argv[1:4]
src = open(path).read()
src = re.sub(r'url "[^"]+"', f'url "{url}"', src, count=1)
src = re.sub(r'sha256 "[a-f0-9]{64}"', f'sha256 "{sha}"', src, count=1)
open(path, "w").write(src)
PY

cd "$TAP_DIR"
if git diff --quiet; then
  echo "==> formula already at $VERSION"
else
  git add Formula/peon-poke.rb
  git commit -q -m "peon-poke $VERSION"
  git push -q
  echo "==> tap pushed: $TAP_REPO @ $VERSION (users: brew upgrade peon-poke)"
fi
