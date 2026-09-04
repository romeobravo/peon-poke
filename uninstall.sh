#!/bin/sh
# peon-poke uninstaller (compatibility shim) — logic lives in the Python
# CLI: `peon-poke uninstall`. Pass --purge to also remove
# ~/.config/peon-poke/config.json.
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$DIR/peon-poke" ]; then
  exec "$DIR/peon-poke" uninstall "$@"
fi
exec "${POKE_DIR:-$HOME/.peon-poke}/bin/peon-poke" uninstall "$@"
