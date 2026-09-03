#!/bin/bash
# test-codex-adapter.sh — dispatch matrix for adapters/codex.sh.
#
# Codex's documented `notify` contract passes ONE JSON argument with a
# "type" field; hook-style callers pass JSON on stdin with
# "hook_event_name". Legacy builds passed a bare event name. All three
# must dispatch; anything unknown must be silently ignored (exit 0).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/pokedir"
cat > "$TMP/pokedir/poke.sh" <<EOF
#!/bin/bash
echo "\$1" >> "$TMP/dispatched"
EOF
chmod +x "$TMP/pokedir/poke.sh"

adapter() { env HOME="$TMP/home" POKE_DIR="$TMP/pokedir" bash "$REPO/adapters/codex.sh" "$@"; }

expect_dispatch() { # expect_dispatch <label> <expected-category> -- <adapter args...>
  local label="$1" want="$2"; shift 2; shift  # drop '--'
  : > "$TMP/dispatched"
  adapter "$@" </dev/null
  [ "$(cat "$TMP/dispatched" 2>/dev/null)" = "$want" ] \
    && { PASS=$((PASS+1)); echo "ok   - $label" ; } \
    || { FAIL=$((FAIL+1)); echo "FAIL - $label: wanted [$want] got [$(cat "$TMP/dispatched" 2>/dev/null)]"; }
}

expect_ignore() { # expect_ignore <label> -- <adapter args...>
  local label="$1"; shift; shift  # drop '--'
  : > "$TMP/dispatched"
  adapter "$@" </dev/null
  [ ! -s "$TMP/dispatched" ] \
    && { PASS=$((PASS+1)); echo "ok   - $label" ; } \
    || { FAIL=$((FAIL+1)); echo "FAIL - $label: dispatched anyway [$(cat "$TMP/dispatched")]"; }
}

stdin_dispatch() { # stdin_dispatch <label> <json-on-stdin> <expected>
  local label="$1" json="$2" want="$3"
  : > "$TMP/dispatched"
  printf '%s' "$json" | env HOME="$TMP/home" POKE_DIR="$TMP/pokedir" bash "$REPO/adapters/codex.sh"
  [ "$(cat "$TMP/dispatched" 2>/dev/null)" = "$want" ] \
    && { PASS=$((PASS+1)); echo "ok   - $label" ; } \
    || { FAIL=$((FAIL+1)); echo "FAIL - $label: wanted [$want] got [$(cat "$TMP/dispatched" 2>/dev/null)]"; }
}

stdin_ignore() {
  local label="$1" json="$2"
  : > "$TMP/dispatched"
  printf '%s' "$json" | env HOME="$TMP/home" POKE_DIR="$TMP/pokedir" bash "$REPO/adapters/codex.sh"
  [ ! -s "$TMP/dispatched" ] \
    && { PASS=$((PASS+1)); echo "ok   - $label" ; } \
    || { FAIL=$((FAIL+1)); echo "FAIL - $label: dispatched anyway [$(cat "$TMP/dispatched")]"; }
}

# --- documented Codex notify payload (single JSON argv) ---
expect_dispatch "JSON argv agent-turn-complete" task.complete -- \
  '{"type":"agent-turn-complete","turn-id":"t1","input_messages":[{"role":"user","content":"hi"}],"last_assistant_message":"done"}'
expect_dispatch "JSON argv error" task.error -- \
  '{"type":"error","message":"boom"}'
expect_ignore  "JSON argv unknown type" -- \
  '{"type":"something-new"}'
expect_ignore  "JSON argv without type" -- \
  '{"turn-id":"t1"}'

# --- legacy bare event name argv ---
expect_dispatch "bare argv agent-turn-complete" task.complete -- agent-turn-complete
expect_dispatch "bare argv error" task.error -- error
expect_ignore  "bare argv unknown" -- some-unknown-event

# --- hook-style JSON on stdin ---
stdin_dispatch "stdin Stop" '{"hook_event_name":"Stop"}' task.complete
stdin_dispatch "stdin SessionStart" '{"hook_event_name":"SessionStart"}' session.start
stdin_dispatch "stdin session_start" '{"hook_event_name":"session_start"}' session.start
stdin_ignore  "stdin unknown" '{"hook_event_name":"Whatever"}'
stdin_ignore  "stdin garbage" 'not json at all'

# --- silence ---
expect_ignore "no argv, no stdin" --

# --- missing poke.sh never fails ---
: > "$TMP/dispatched"
env HOME="$TMP/home" POKE_DIR="$TMP/does-not-exist" bash "$REPO/adapters/codex.sh" \
  '{"type":"agent-turn-complete"}' </dev/null
if [ $? -eq 0 ] && [ ! -s "$TMP/dispatched" ]; then
  PASS=$((PASS+1)); echo "ok   - missing poke.sh exits 0 silently"
else
  FAIL=$((FAIL+1)); echo "FAIL - missing poke.sh must exit 0 silently"
fi

echo "----"
echo "adapter: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
