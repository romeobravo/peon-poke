#!/bin/sh
# peon-poke dispatcher (compatibility shim).
#
# The dispatch logic lives in the Python CLI (peon-poke dispatch); this shim
# exists so hook registrations and user wiring predating the CLI keep
# working unchanged. Resolution: a repo checkout runs the sibling CLI; an
# installed runtime uses $POKE_DIR/bin/peon-poke.
#
# Usage: poke.sh <category>   e.g. poke.sh task.complete
#        poke.sh <pattern>    name or raw gaps, e.g. poke.sh 60,120,40
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$DIR/peon-poke" ]; then
  exec "$DIR/peon-poke" dispatch "$@"
fi
exec "${POKE_DIR:-$HOME/.peon-poke}/bin/peon-poke" dispatch "$@"
