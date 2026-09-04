#!/bin/bash
# release.sh — cut a peon-poke release end to end.
#
# Usage: scripts/release.sh <X.Y.Z> ["commit message"]
#
# Flow: preflight -> rebuild -> refresh dist/poke-darwin-universal ->
# regenerate SHA256SUMS -> bump VERSION -> commit everything ->
# tag vX.Y.Z -> push main + tag -> gh release create -> brew-bump the tap.
#
# Ordering matters: install-remote.sh hard-requires SHA256SUMS at the
# release tag, so the tag must exist before anyone curls the installer.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

die() { echo "release: $*" >&2; exit 1; }

VERSION="${1:-}"
[ -n "$VERSION" ] || die "usage: scripts/release.sh <X.Y.Z> [\"commit message\"]"
VERSION="${VERSION#v}"
MSG="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like X.Y.Z (got '$VERSION')"

# --- preflight ---
[ "$(uname -m)" = "arm64" ] || die "dist binary is arm64-only — release from an Apple Silicon Mac"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "not on main"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && die "tag v$VERSION already exists locally"
[ -z "$(git ls-remote --tags origin "refs/tags/v$VERSION")" ] || die "tag v$VERSION already exists on origin"
# A release must contain exactly its own changes: require a clean
# worktree (checked BEFORE the build dirties it) and a main in sync with
# origin, so no forgotten local edit rides along in the release commit
# or the rebuilt binary.
[ -z "$(git status --porcelain)" ] || die "worktree not clean — commit or stash first"
git fetch -q origin || die "cannot fetch origin"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || die "local main does not match origin/main — pull/push first"
command -v gh >/dev/null 2>&1 || die "gh CLI not found"
gh auth status >/dev/null 2>&1 || die "gh not authenticated"
command -v clang >/dev/null 2>&1 || die "clang not found"

# --- rebuild + refresh shipped artifacts ---
echo "==> building"
make clean >/dev/null
make >/dev/null
make dist >/dev/null
echo "==> dist/poke-darwin-universal refreshed (arm64 + x86_64, min macOS $(make -s print-min))"

bash scripts/sha256sums.sh >/dev/null
echo "==> SHA256SUMS regenerated"

echo "$VERSION" > VERSION

# --- commit, tag, push ---
# Stage exactly what this release regenerated — never `git add -A`.
# (Anything else that belongs in the release is already committed,
# enforced by the clean-worktree preflight.)
git add VERSION SHA256SUMS dist/poke-darwin-universal
git diff --cached --quiet && die "nothing to commit for v$VERSION"
if [ -n "$MSG" ]; then
  git commit -q -m "v$VERSION: $MSG"
else
  git commit -q -m "v$VERSION"
fi
git tag -a "v$VERSION" -m "peon-poke v$VERSION"
echo "==> committed + tagged v$VERSION"

git push -q origin main
git push -q origin "v$VERSION"
echo "==> pushed main + tag"

gh release create "v$VERSION" --title "v$VERSION" --generate-notes
echo "==> GitHub release created"

bash scripts/brew-bump.sh "$VERSION"
echo "==> done: v$VERSION released, Homebrew tap bumped"
