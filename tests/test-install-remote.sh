#!/bin/bash
# test-install-remote.sh — the remote installer's manifest hardening.
#
# A hostile SHA256SUMS must not be able to make the bootstrap fetch or
# write outside its temp dir: ../ traversal, absolute paths, "."/".."
# components, backslashes, odd characters, and unexpected top-level
# names must all abort BEFORE any payload byte is fetched. The bootstrap
# is exercised for real over a file:// PEON_POKE_BASE — no network, no
# GitHub API (PEON_POKE_BASE short-circuits tag resolution).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

BASE="$TMP/serve"   # fake release tag
mkdir -p "$BASE"

run_install() { # run_install <manifest-body> — leaves rc in RI_RC, output in RI_OUT
  printf '%s' "$1" > "$BASE/SHA256SUMS"
  RI_OUT="$(env PEON_POKE_BASE="file://$BASE" bash "$REPO/install-remote.sh" 2>&1)"
  RI_RC=$?
}

expect_abort() { # expect_abort <label> <manifest-body>
  run_install "$2"
  if [ "$RI_RC" != 0 ] && printf '%s' "$RI_OUT" | grep -q "lists invalid or unexpected path"; then
    ok "$1"
  else
    bad "$1 (rc=$RI_RC: $(printf '%s' "$RI_OUT" | head -n 2))"
  fi
}

# --- the audit's reproduction: ../ traversal out of $TMP --------------------
OUTSIDE="$TMP/outside"
mkdir -p "$OUTSIDE"
expect_abort "manifest ../ traversal rejected" \
  'hash  ../../../outside/escaped-by-manifest.txt
'
[ ! -e "$OUTSIDE/escaped-by-manifest.txt" ] \
  && ok "traversal attempt wrote nothing outside TMP" || bad "traversal wrote outside TMP"

# --- other hostile shapes -----------------------------------------------------
expect_abort "absolute manifest path rejected"        'hash  /etc/passwd
'
expect_abort "embedded .. component rejected"         'hash  dist/../../out.txt
'
expect_abort "bare '..' rejected"                     'hash  ..
'
expect_abort "bare '.' rejected"                      'hash  .
'
expect_abort "leading './' rejected"                  'hash  ./install.sh
'
expect_abort "backslash rejected"                     'hash  plugin\poke.ts
'
expect_abort "whitespace-bearing path rejected"       'hash  in stall.sh
'
expect_abort "unexpected top-level name rejected"     'hash  Makefile
'
expect_abort "unexpected top-level dir rejected"      'hash  src/poke.c
'
expect_abort "manifest self-reference rejected"       'hash  SHA256SUMS
'

# --- control: a well-formed entry passes validation and reaches fetch -------
run_install 'deadbeef  dist/poke-darwin-universal
'
if [ "$RI_RC" != 0 ] && printf '%s' "$RI_OUT" | grep -q "failed to fetch dist/poke-darwin-universal"; then
  ok "valid manifest path passes validation (reaches fetch)"
else
  bad "valid manifest path blocked by validation (rc=$RI_RC: $RI_OUT)"
fi

echo "----"
echo "install-remote: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
