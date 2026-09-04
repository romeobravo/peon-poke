#!/bin/bash
# test-codex-setup.sh — TOML fixtures for peon-poke setup's Codex
# config.toml notify registration: empty,
# table-ending, existing top-level notify, malformed, idempotency, paths
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

# Isolation: setup exposes the uninstall command via the first writable
# dir of ~/.local/bin, ~/bin, /usr/local/bin that is on PATH (first
# match wins). Prepending a fake ~/.local/bin makes it the winner and
# leaves the real /usr/local/bin unreachable — while keeping the rest of
# PATH intact so setup's python/tomllib discovery still works. (An
# earlier suite version briefly replaced the real global
# peon-poke-uninstall symlink during a run.)
run_setup() {
  mkdir -p "$H/.local/bin"
  env HOME="$H" PATH="$H/.local/bin:$PATH" "$REPO/peon-poke" setup >>"$TMP/setup.log" 2>&1
}

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
grep -q '^notify = \[".*bin/peon-poke", "codex"\]' "$H/.codex/config.toml" \
  && ok "empty config: notify written (CLI shape)" || bad "empty config: notify missing"
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
rm -rf "$WEIRD"; mkdir -p "$WEIRD/.codex" "$WEIRD/.local/bin"
env HOME="$WEIRD" PATH="$WEIRD/.local/bin:$PATH" "$REPO/peon-poke" setup >>"$TMP/setup.log" 2>&1
CFG="$WEIRD/.codex/config.toml"
if [ -n "$TOML_PY" ]; then
  "$TOML_PY" - "$CFG" "$WEIRD" > "$TMP/weird.out" <<'PY'
import os, sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
n = d.get("notify", [])
want = [os.path.join(sys.argv[2], ".peon-poke", "bin", "peon-poke"), "codex"]
print("yes" if n == want else "no")
PY
  R="$(cat "$TMP/weird.out")"
  [ "$R" = "yes" ] && ok "quoted/space path: valid TOML, correct unescaped path" || bad "quoted/space path: $R"
else
  grep -q 'notify = \[".*\\"quote\\".*bin/peon-poke", "codex"\]' "$CFG" \
    && ok "quoted/space path: properly escaped in TOML" || bad "quoted/space path: bad escaping"
fi
# the installed CLI must run from the quoted path and dispatch
mkdir -p "$WEIRD/stub"
cat > "$WEIRD/stub/poke" <<EOF
#!/bin/bash
echo "\$1" >> "$TMP/weird-fired"
EOF
chmod +x "$WEIRD/stub/poke"
env HOME="$WEIRD" POKE_BIN="$WEIRD/stub/poke" \
  "$WEIRD/.peon-poke/bin/peon-poke" codex '{"type":"agent-turn-complete"}' >/dev/null 2>&1 </dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/weird-fired" ] && break; sleep 0.1; done
[ "$(cat "$TMP/weird-fired" 2>/dev/null)" = "fortune" ] \
  && ok "quoted/space path: CLI runs from quoted path and dispatches" \
  || bad "quoted/space path: CLI dispatch failed ($(cat "$TMP/weird-fired" 2>/dev/null))"

# ------------------------------------- mis-placed managed registration ---
# A managed block that landed after a table header (hand-moved, or written
# there by an old setup) must be re-registered at top level.

cat > "$TMP/initial.toml" <<EOF
model = "gpt-5"

[tui]
notifications = true

# peon-poke (managed — remove to uninstall)
notify = ["$H/.peon-poke/bin/peon-poke", "codex"]
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
print("yes" if "notify" not in tui and d["notify"][0].endswith("/bin/peon-poke")
      and d["notify"][1] == "codex" else "no")
PY
  R="$(cat "$TMP/tui.out")"
  [ "$R" = "yes" ] && ok "migration: [tui] no longer contains notify" || bad "migration: [tui] still contains notify"
fi

# --------------------------------------- comment-spoofed foreign notify ---
# Ownership must be decided on the comment-stripped assignment: a
# foreign notify followed by a comment mentioning our adapter path is
# the USER's notify and must be preserved, not hijacked as ours.
cat > "$TMP/initial.toml" <<EOF
notify = ["/usr/bin/true"] # $H/.peon-poke/adapters/codex.sh
model = "gpt-5"
EOF
scenario; run_setup
grep -q '/usr/bin/true' "$H/.codex/config.toml" \
  && ok "comment-spoofed foreign notify preserved by setup" \
  || bad "setup hijacked a comment-spoofed foreign notify"
cmp -s "$TMP/initial.toml" "$H/.codex/config.toml" \
  && ok "comment-spoofed foreign notify byte-identical after setup" \
  || bad "setup rewrote the comment-spoofed notify config"

echo "----"
echo "setup: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
