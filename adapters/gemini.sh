#!/bin/sh
# peon-poke adapter for Gemini CLI (compatibility shim).
# Event mapping lives in the Python CLI: `peon-poke gemini`.
# Gemini hook events arrive as argv (e.g. adapters/gemini.sh SessionStart).
exec "${POKE_DIR:-$HOME/.peon-poke}/bin/peon-poke" gemini "$@"
