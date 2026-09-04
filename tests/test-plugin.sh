#!/bin/bash
# test-plugin.sh — the pi/oh-my-pi extension (plugins/pi/poke.ts).
#
# 1. transpiles cleanly (bun build gate),
# 2. registers agent_settled + ui_prompt_start and actually fires the
#    CLI dispatcher (stub bin/peon-poke records the category),
# 3. survives a MISSING install dir: spawn() failures arrive as async
#    'error' events — without a listener, bun crashes the host process
#    (verified: old plugin shape exits 1). The extension must exit 0.
# 4. POKE_ARGS bypass mode drives bin/poke directly.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

if ! command -v bun >/dev/null 2>&1; then
  echo "plugin: SKIPPED (bun not found)"
  exit 0
fi

PLUGIN="$REPO/plugins/pi/poke.ts"
HARNESS="$HERE/fixtures/plugin-harness.ts"

# --- 1. build gate --------------------------------------------------------
if bun build --target=bun "$PLUGIN" --outfile "$TMP/poke.built.js" >/dev/null 2>&1; then
  ok "plugin transpiles (bun build)"
else
  bad "plugin does not transpile"
fi

# --- 2. fires dispatcher with correct categories -------------------------
mkdir -p "$TMP/pokedir/bin"
cat > "$TMP/pokedir/bin/peon-poke" <<EOF
#!/bin/bash
echo "\$2" >> "$TMP/fired"
EOF
chmod +x "$TMP/pokedir/bin/peon-poke"
OUT="$(env HOME="$TMP/home" POKE_DIR="$TMP/pokedir" bun "$HARNESS" "$PLUGIN" 2>&1)"
RC=$?
if [ $RC = 0 ]; then
  ok "harness run exits 0 with working dispatcher"
else
  bad "harness run exited $RC: $OUT"
fi
echo "$OUT" | grep -q "registered: agent_settled,ui_prompt_start" \
  && ok "registers agent_settled + ui_prompt_start" || bad "event registration: $OUT"
sort "$TMP/fired" 2>/dev/null | tr '\n' ' ' | grep -q "input.required task.complete" \
  && ok "agent_settled -> task.complete, ui_prompt_start -> input.required" \
  || bad "dispatch categories: $(cat "$TMP/fired" 2>/dev/null)"

# --- 3. missing install dir must not crash the host ----------------------
# (regression: async spawn ENOENT with no 'error' listener killed bun —
# reachable via the POKE_ARGS branch, which spawns bin/poke directly)
OUT="$(env HOME="$TMP/home" POKE_DIR="$TMP/does-not-exist" POKE_ARGS="boop" bun "$HARNESS" "$PLUGIN" 2>&1)"
RC=$?
if [ $RC = 0 ] && ! printf '%s' "$OUT" | grep -q ENOENT; then
  ok "missing install dir: no crash, no unhandled spawn error"
elif [ $RC = 0 ]; then
  ok "missing install dir: no crash (ENOENT reported but handled)"
else
  bad "missing install dir crashed the host (exit $RC): $OUT"
fi

# --- 4. POKE_ARGS bypass --------------------------------------------------
mkdir -p "$TMP/argsdir/bin"
cat > "$TMP/argsdir/bin/poke" <<EOF
#!/bin/bash
echo "argc=\$# args=<\$*>" >> "$TMP/argslog"
EOF
chmod +x "$TMP/argsdir/bin/poke"
env HOME="$TMP/home" POKE_DIR="$TMP/argsdir" POKE_ARGS="fortune extra" \
  bun "$HARNESS" "$PLUGIN" >/dev/null 2>&1
sleep 0.3
# both events fire -> two identical invocations of bin/poke with ARGS
[ "$(wc -l < "$TMP/argslog" | tr -d ' ')" = 2 ] \
  && [ "$(sort -u "$TMP/argslog" | wc -l | tr -d ' ')" = 1 ] \
  && [ "$(head -n 1 "$TMP/argslog")" = "argc=2 args=<fortune extra>" ] \
  && ok "POKE_ARGS bypasses poke.sh with explicit args" \
  || bad "POKE_ARGS: $(cat "$TMP/argslog" 2>/dev/null)"

echo "----"
echo "plugin: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
