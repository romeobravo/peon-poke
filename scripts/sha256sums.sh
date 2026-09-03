#!/bin/bash
# sha256sums.sh — regenerate SHA256SUMS for the remote installer.
#
# install-remote.sh fetches exactly the files listed in SHA256SUMS and
# verifies each against it, so this must be re-run (and committed)
# whenever any fetched runtime file changes — and always before tagging
# a release. Run it after rebuilding dist/poke-darwin-arm64.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

shasum -a 256 \
  install.sh \
  peon-poke-setup \
  poke.sh \
  config.json \
  dist/poke-darwin-arm64 \
  plugins/pi/*.ts \
  adapters/*.sh \
  > SHA256SUMS

echo "==> SHA256SUMS written:"
cat SHA256SUMS
