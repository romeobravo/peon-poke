#!/bin/bash
# sha256sums.sh — regenerate SHA256SUMS for the remote installer.
#
# install-remote.sh fetches exactly the files listed in SHA256SUMS and
# verifies each against it, so this must be re-run (and committed)
# whenever any fetched runtime file changes — and always before tagging
# a release. Run it after rebuilding dist/poke-darwin-universal (make dist).
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

shasum -a 256 \
  install.sh \
  peon-poke \
  config.json \
  dist/poke-darwin-universal \
  plugins/pi/*.ts \
  plugins/opencode/*.ts \
  adapters/*.sh \
  > SHA256SUMS

echo "==> SHA256SUMS written:"
cat SHA256SUMS
