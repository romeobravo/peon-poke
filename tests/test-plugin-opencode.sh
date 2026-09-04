#!/bin/bash
# test-plugin-opencode.sh — plugins/opencode/peon-poke.ts.
#
# 1. transpiles cleanly (bun build gate),
# 2. event hook maps opencode events to poke categories
#    (session.idle -> task.complete, session.error -> task.error,
#     permission.updated -> input.required, session.created -> session.start)
#    and ignores unknown events,
# 3. survives a missing install dir (async spawn errors never crash host).
#
# The real end-to-end (actual opencode 1.18 session firing the plugin) was
# verified manually during development; this fixture pins the contract.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

if ! command -v bun >/dev/null 2>&1; then
  echo "plugin-opencode: SKIPPED (bun not found)"
  exit 0
fi

PLUGIN="$REPO/plugins/opencode/peon-poke.ts"
HARNESS="$HERE/fixtures/plugin-harness-opencode.ts"

# --- 1. build gate --------------------------------------------------------
if bun build --target=bun "$PLUGIN" --outfile "$TMP/built.js" >/dev/null 2>&1; then
  ok "plugin transpiles (bun build)"
else
  bad "plugin does not transpile"
fi

# --- 2 + 3. harness run ---------------------------------------------------
mkdir -p "$TMP/pokedir/bin"
cat > "$TMP/pokedir/bin/peon-poke" <<EOF
#!/bin/bash
echo "\$2" >> "$TMP/fired"
EOF
chmod +x "$TMP/pokedir/bin/peon-poke"

OUT="$(env HOME="$TMP/home" POKE_DIR="$TMP/pokedir" bun "$HARNESS" "$PLUGIN" 2>&1)"
RC=$?
[ $RC = 0 ] && echo "$OUT" | grep -q "event hook registered" \
  && ok "harness run exits 0, event hook registered" \
  || bad "harness run failed (exit $RC): $OUT"

GOT="$(sort "$TMP/fired" 2>/dev/null | tr '\n' ' ')"
WANT="input.required session.start task.complete task.error "
[ "$GOT" = "$WANT" ] \
  && ok "event -> category mapping correct, unknown events ignored" \
  || bad "mapping: got [$GOT] want [$WANT]"

# --- missing install dir: no crash ----------------------------------------
OUT="$(env HOME="$TMP/home" POKE_DIR="$TMP/does-not-exist" bun "$HARNESS" "$PLUGIN" 2>&1)"
RC=$?
if [ $RC = 0 ]; then
  ok "missing install dir: no crash"
else
  bad "missing install dir crashed (exit $RC): $OUT"
fi

echo "----"
echo "plugin-opencode: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
