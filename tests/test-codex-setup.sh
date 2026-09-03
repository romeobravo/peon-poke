#!/bin/bash
# test-codex-setup.sh — TOML fixtures for peon-poke-setup's Codex
# registration: empty, table-ending, existing top-level notify, malformed,
# idempotency, and paths with spaces/quotes.
#
# Uses a fully isolated HOME; nothing here touches the real ~/.codex.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"

ok()   { PASS=$((PASS+1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

run_setup() { env HOME="$H" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1; }

# a python with tomllib if any exists (python3 may be < 3.11 on macOS)
TOML_PY=""
for p in python3 python3.13 python3.12 python3.11 /opt/homebrew/bin/python3; do
  command -v "$p" >/dev/null 2>&1 && "$p" -c 'import tomllib' 2>/dev/null && { TOML_PY="$p"; break; }
done

# validity check: real TOML parser when available, else structural checks
# (BWK awk has no \s — use [ \t])
toml_notify_toplevel() { # file -> prints "yes"/"no"/"dup"/"invalid"
  local f="$1"
  if [ -n "$TOML_PY" ]; then
    "$TOML_PY" - "$f" <<'PY'
import sys, tomllib
try:
    d = tomllib.load(open(sys.argv[1], "rb"))
except Exception:
    print("invalid"); raise SystemExit
if "notify" not in d:
    print("no"); raise SystemExit
v = d["notify"]
# exactly one top-level notify; "ours" vs "user's" is asserted by grep
print("yes" if isinstance(v, list) and len(v) >= 1 else "weird")
PY
  else
    awk '
      /^[ \t]*\[/ { intable = 1 }
      intable != 1 && /^[ \t]*notify[ \t]*=/ { n++ }
      END { if (n == 0) print "no"; else if (n == 1) print "yes"; else print "dup" }
    ' "$f"
  fi
}

scenario() { # scenario <name> — resets HOME with $TMP/initial.toml (if any)
  rm -rf "$H"; mkdir -p "$H/.codex"
  [ -f "$TMP/initial.toml" ] && cp "$TMP/initial.toml" "$H/.codex/config.toml"
}

# ---------------------------------------------------------------- empty ---
: > "$TMP/initial.toml"; scenario
run_setup
grep -q '^notify = \["bash",.*adapters/codex.sh"\]' "$H/.codex/config.toml" \
  && ok "empty config: notify written" || bad "empty config: notify missing"
[ "$(toml_notify_toplevel "$H/.codex/config.toml")" = "yes" ] \
  && ok "empty config: valid top-level TOML" || bad "empty config: $(toml_notify_toplevel "$H/.codex/config.toml")"

# ------------------------------------------------------- table-ending ---
cat > "$TMP/initial.toml" <<'EOF'
model = "gpt-5"
approval_policy = "on-request"

[tui]
notifications = true

[sandbox_workspace_write]
network_access = true
EOF
scenario; run_setup
[ "$(toml_notify_toplevel "$H/.codex/config.toml")" = "yes" ] \
  && ok "table-ending config: notify at TOP level (not inside [tui])" \
  || bad "table-ending config: notify not top-level ($(toml_notify_toplevel "$H/.codex/config.toml"))"
python3 - "$H/.codex/config.toml" <<'PY' 2>/dev/null && ok "table-ending config: tables untouched" || bad "table-ending config: tables mangled"
import sys
src = open(sys.argv[1]).read()
assert '[tui]\nnotifications = true' in src
assert '[sandbox_workspace_write]\nnetwork_access = true' in src
assert src.index('notify =') < src.index('[tui]')
PY
[ -f "$H/.codex/config.toml.peon-poke-bak" ] \
  && ok "backup written before modification" || bad "no backup written"

# --------------------------------------------------- existing top notify ---
cat > "$TMP/initial.toml" <<'EOF'
notify = ["python3", "-m", "my_notifier"]
model = "gpt-5"
EOF
scenario; run_setup
[ "$(toml_notify_toplevel "$H/.codex/config.toml")" = "yes" ] \
  && ok "existing notify: preserved, NOT duplicated" \
  || bad "existing notify: duplicated/invalid ($(toml_notify_toplevel "$H/.codex/config.toml"))"
grep -q 'my_notifier' "$H/.codex/config.toml" \
  && ok "existing notify: user command intact" || bad "existing notify: user command clobbered"
[ ! -f "$H/.codex/config.toml.peon-poke-bak" ] \
  && ok "existing notify: file left unmodified (no backup needed)" || bad "existing notify: file was touched"

# ------------------------------------------------------------ malformed ---
printf 'this is [ not = valid toml\n' > "$TMP/initial.toml"; scenario; run_setup
if [ -n "$TOML_PY" ]; then
  cmp -s "$TMP/initial.toml" "$H/.codex/config.toml" \
    && ok "malformed TOML: left byte-identical" || bad "malformed TOML: modified anyway"
else
  ok "malformed TOML: skipped (no tomllib-capable python found)"
fi
# ---------------------------------------------------------- idempotent ---
cat > "$TMP/initial.toml" <<'EOF'
model = "gpt-5"
EOF
scenario; run_setup
cp "$H/.codex/config.toml" "$TMP/once.toml"
run_setup  # second run must not re-register
[ "$(toml_notify_toplevel "$H/.codex/config.toml")" = "yes" ] \
  && ok "second setup run: still exactly one notify" \
  || bad "second setup run: $(toml_notify_toplevel "$H/.codex/config.toml"))"
cmp -s "$TMP/once.toml" "$H/.codex/config.toml" \
  && ok "second setup run: idempotent (byte-identical)" || bad "second setup run: file changed"

# --------------------------------------------- no temp files left behind ---
ls "$H/.codex/" | grep -q '^\.config\.toml\.' \
  && bad "atomic-write temp file leaked" || ok "no atomic-write temp files leaked"

# -------------------------------------------------- quoted/spacey paths ---
WEIRD="$TMP/home with space and \"quote\""
rm -rf "$WEIRD"; mkdir -p "$WEIRD/.codex"
env HOME="$WEIRD" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1
CFG="$WEIRD/.codex/config.toml"
if [ -n "$TOML_PY" ]; then
  "$TOML_PY" - "$CFG" "$WEIRD" > "$TMP/weird.out" <<'PY'
import os, sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
n = d.get("notify", [])
want = ["bash", os.path.join(sys.argv[2], ".peon-poke", "adapters", "codex.sh")]
print("yes" if n == want else "no")
PY
  R="$(cat "$TMP/weird.out")"
  [ "$R" = "yes" ] && ok "quoted/space path: valid TOML, correct unescaped path" || bad "quoted/space path: $R"
else
  grep -q 'notify = \["bash", ".*\\"quote\\".*adapters/codex.sh"\]' "$CFG" \
    && ok "quoted/space path: properly escaped in TOML" || bad "quoted/space path: bad escaping"
fi
bash "$WEIRD/.peon-poke/adapters/codex.sh" '{"type":"agent-turn-complete"}' >/dev/null 2>&1 </dev/null \
  && ok "quoted/space path: adapter runs from quoted path" || bad "quoted/space path: adapter fails"

# --------------------------------------------- old-buggy registrations ---
# Setups <= v0.4.4 appended the block at EOF without TOML awareness.

# (a) after a table header: must be MOVED to top level
cat > "$TMP/initial.toml" <<EOF
model = "gpt-5"

[tui]
notifications = true

# peon-poke (managed — remove to uninstall)
notify = ["bash", "$H/.peon-poke/adapters/codex.sh"]
EOF
scenario; run_setup
[ "$(toml_notify_toplevel "$H/.codex/config.toml")" = "yes" ] \
  && ok "migration: table-scoped block moved to top level" \
  || bad "migration: block still mis-scoped ($(toml_notify_toplevel "$H/.codex/config.toml"))"
if [ -n "$TOML_PY" ]; then
  "$TOML_PY" - "$H/.codex/config.toml" > "$TMP/tui.out" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
tui = d.get("tui", {})
print("yes" if "notify" not in tui and d["notify"][1].endswith("/adapters/codex.sh") else "no")
PY
  R="$(cat "$TMP/tui.out")"
  [ "$R" = "yes" ] && ok "migration: [tui] no longer contains notify" || bad "migration: [tui] still contains notify"
fi

# (b) duplicated after a user's top-level notify: must heal to valid TOML
cat > "$TMP/initial.toml" <<EOF
notify = ["python3", "-m", "my_notifier"]
model = "gpt-5"

# peon-poke (managed — remove to uninstall)
notify = ["bash", "$H/.peon-poke/adapters/codex.sh"]
EOF
scenario; run_setup
[ "$(toml_notify_toplevel "$H/.codex/config.toml")" = "yes" ] \
  && ok "migration: duplicate-key config healed to exactly one notify" \
  || bad "migration: still broken ($(toml_notify_toplevel "$H/.codex/config.toml"))"
grep -q 'my_notifier' "$H/.codex/config.toml" \
  && ok "migration: user notifier survived the heal" || bad "migration: user notifier lost"
grep -q 'peon-poke/adapters/codex.sh' "$H/.codex/config.toml" \
  && bad "migration: our stray duplicate remains" || ok "migration: our stray duplicate removed"

echo "----"
echo "setup: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
