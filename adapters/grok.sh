#!/bin/sh
# peon-poke adapter for Grok Build (compatibility shim).
# Event mapping lives in the Python CLI: `peon-poke grok`.
# Grok sends camelCase stdin JSON (hookEventName); stdin passes through exec.
exec "${POKE_DIR:-$HOME/.peon-poke}/bin/peon-poke" grok "$@"
