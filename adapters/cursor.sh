#!/bin/sh
# peon-poke adapter for Cursor IDE (compatibility shim).
# Event mapping lives in the Python CLI: `peon-poke cursor`.
# Wire the events you want in ~/.cursor/hooks.json (see README).
exec "${POKE_DIR:-$HOME/.peon-poke}/bin/peon-poke" cursor "$@"
