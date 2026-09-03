#!/bin/bash
# run-all.sh — full peon-poke test suite. Builds first, then runs every
# tests/test-*.sh. Any failure fails the run.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

echo "==> building"
make -C "$REPO" >/dev/null || { echo "build failed" >&2; exit 1; }

RC=0
for t in "$HERE"/test-*.sh; do
  [ -x "$t" ] || chmod +x "$t"
  echo
  echo "==> $(basename "$t")"
  bash "$t" || RC=1
done

echo
[ "$RC" = 0 ] && echo "ALL TESTS PASSED" || echo "TESTS FAILED"
exit $RC
