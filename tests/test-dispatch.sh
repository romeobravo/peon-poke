#!/bin/bash
# test-dispatch.sh — pattern dispatch through the Python CLI (poke.sh
# execs `peon-poke dispatch`; malformed-config cases exercise the CLI
# directly, which is the shape hooks invoke).
# Config patterns are single spec strings ("[60, 120, 40]", "boop"); the
# dispatcher must pass them as ONE argument. Unquoted expansion used to
# split spaced lists (bin/poke reads argv[1] only -> truncated pattern)
# and glob-expand stray "*". Dispatch must ALWAYS exit 0, even on a
# hand-mangled config.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"

ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

cat > "$TMP/stub-poke" <<EOF
#!/bin/bash
echo "argc=\$# args=<\$*>" >> "$TMP/log"
EOF
chmod +x "$TMP/stub-poke"

dispatch() { # dispatch <token> [expect-fire:1|0]  (leaves result in $TMP/log)
  local tok="$1" expect="${2:-1}" i
  : > "$TMP/log"
  ( cd "$TMP/cwd" && env HOME="$H" POKE_BIN="$TMP/stub-poke" \
      bash "$REPO/poke.sh" "$tok" ) >/dev/null 2>&1
  # the real dispatcher fires detached — poll for the stub to land
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [ "$expect" = 1 ] && [ -s "$TMP/log" ]; then break; fi
    sleep 0.05
  done
}

cfg() { printf '%s' "$1" > "$H/.config/peon-poke/config.json"; }

mkdir -p "$H/.config/peon-poke" "$TMP/cwd"
touch "$TMP/cwd/alpha.txt" "$TMP/cwd/beta.txt"

# --- spaced bracketed list: ONE argument, brackets/spaces intact --------
cfg '{"categories":{"task.complete":true},"patterns":{"task.complete":"[60, 120, 40]"}}'
dispatch task.complete
[ "$(cat "$TMP/log")" = 'argc=1 args=<[60, 120, 40]>' ] \
  && ok "spaced bracketed pattern passed as a single argument" \
  || bad "spaced bracketed pattern split: $(cat "$TMP/log")"

# --- compact list --------------------------------------------------------
cfg '{"categories":{"task.complete":true},"patterns":{"task.complete":"60,120,40"}}'
dispatch task.complete
[ "$(cat "$TMP/log")" = 'argc=1 args=<60,120,40>' ] \
  && ok "compact gap list as single argument" || bad "compact list: $(cat "$TMP/log")"

# --- named pattern -------------------------------------------------------
cfg '{"categories":{"task.complete":true},"patterns":{"task.complete":"fortune"}}'
dispatch task.complete
[ "$(cat "$TMP/log")" = 'argc=1 args=<fortune>' ] \
  && ok "named pattern as single argument" || bad "named pattern: $(cat "$TMP/log")"

# --- glob-bearing pattern must NOT expand --------------------------------
cfg '{"categories":{"task.complete":true},"patterns":{"task.complete":"*"}}'
dispatch task.complete
[ "$(cat "$TMP/log")" = 'argc=1 args=<*>' ] \
  && ok "glob '*' stays literal (no expansion)" || bad "glob expanded: $(cat "$TMP/log")"

# --- custom name resolves (still one arg) ---------------------------------
cfg '{"categories":{"task.complete":true},"patterns":{"task.complete":"doorbell"},"custom":{"doorbell":"200, 700, 200, 700"}}'
dispatch task.complete
[ "$(cat "$TMP/log")" = 'argc=1 args=<200, 700, 200, 700>' ] \
  && ok "custom pattern with spaces resolved to single argument" \
  || bad "custom pattern: $(cat "$TMP/log")"

# --- pattern-name mode (no category gating) ------------------------------
cfg '{"categories":{"task.complete":false},"custom":{"doorbell":"60,120"}}'
dispatch doorbell
[ "$(cat "$TMP/log")" = 'argc=1 args=<60,120>' ] \
  && ok "pattern-name mode bypasses category gate" || bad "pattern-name mode: $(cat "$TMP/log")"

# --- gated category stays silent ------------------------------------------
cfg '{"categories":{"task.complete":false},"patterns":{"task.complete":"boop"}}'
dispatch task.complete 0
[ ! -s "$TMP/log" ] && ok "disabled category does not dispatch" || bad "disabled category fired"

# --- enabled:false master switch ------------------------------------------
cfg '{"enabled":false,"categories":{"task.complete":true},"patterns":{"task.complete":"boop"}}'
dispatch task.complete 0
[ ! -s "$TMP/log" ] && ok "enabled:false silences everything" || bad "fired while disabled"

# --- malformed config shapes: never crash, always exit 0 ----------------
# Wrong shapes (list/string where an object belongs) used to raise
# AttributeError and exit 1 — failing the host agent's hook on every turn.
for bad in \
  '{"categories":["task.complete"],"patterns":{"task.complete":"boop"}}' \
  '{"categories":{"task.complete":true},"patterns":["task.complete"]}' \
  '{"custom":"boop"}' \
  '["not","an","object"]' ; do
  cfg "$bad"
  ( cd "$TMP/cwd" && env HOME="$H" POKE_BIN="$TMP/stub-poke" \
      python3 "$REPO/peon-poke" dispatch task.complete ) >"$TMP/bad.out" 2>&1
  rc=$?
  if [ "$rc" = 0 ] && ! grep -q "Traceback" "$TMP/bad.out"; then
    ok "malformed config shape exits 0 quietly: $bad"
  else
    bad "malformed config crashed (rc=$rc): $bad"
  fi
done
# a gated category under a broken patterns section stays silent
cfg '{"categories":{"task.complete":true},"patterns":["task.complete"]}'
dispatch task.complete 0
sleep 0.2
[ ! -s "$TMP/log" ] && ok "gated category silent under malformed patterns" \
  || bad "fired on malformed patterns"

echo "----"
echo "dispatch: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
