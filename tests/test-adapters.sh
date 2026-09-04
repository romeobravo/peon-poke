#!/bin/bash
# test-adapters.sh — dispatch matrix for the CLI's agent adapters
# (peon-poke codex|gemini|cursor|grok — the shims in adapters/ are 2-line
# exec trampolines to these subcommands).
#
# Codex's documented `notify` contract passes ONE JSON argument with a
# "type" field; hook-style callers pass JSON on stdin with a
# "hook_event_name" field; Grok uses camelCase "hookEventName"; Gemini and
# Cursor pass the bare event name as argv. All spellings must dispatch;
# anything unknown must be silently ignored (exit 0).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"

ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

mkdir -p "$H/.config/peon-poke"
cat > "$H/.config/peon-poke/config.json" <<'EOF'
{
  "enabled": true,
  "categories": {"session.start": true, "task.acknowledge": true,
                 "task.complete": true, "task.error": true, "input.required": true},
  "patterns": {"session.start": "p-start", "task.acknowledge": "p-ack",
               "task.complete": "p-done", "task.error": "p-error",
               "input.required": "p-input"}
}
EOF

cat > "$TMP/stub-poke" <<EOF
#!/bin/bash
echo "\$1" >> "$TMP/dispatched"
EOF
chmod +x "$TMP/stub-poke"

cli() { env HOME="$H" POKE_BIN="$TMP/stub-poke" "$REPO/peon-poke" "$@"; }

collect() { # <label> <expected-pattern> -- <cli args...> [stdin via printf pipe]
  local label="$1" want="$2"; shift 2; shift  # drop '--'
  : > "$TMP/dispatched"
  cli "$@" >/dev/null 2>&1 </dev/null
  wait_for_log
  [ "$(cat "$TMP/dispatched" 2>/dev/null)" = "$want" ] \
    && { ok "$label"; return 0; }
  { bad "$label: wanted [$want] got [$(cat "$TMP/dispatched" 2>/dev/null)]"; return 1; }
}

expect_ignore() { # <label> -- <cli args...>
  local label="$1"; shift; shift
  : > "$TMP/dispatched"
  cli "$@" >/dev/null 2>&1 </dev/null
  wait_for_log
  [ ! -s "$TMP/dispatched" ] \
    && ok "$label" || bad "$label: dispatched anyway [$(cat "$TMP/dispatched")]"
}

stdin_collect() { # <label> <json-on-stdin> <expected-pattern|''>
  local label="$1" json="$2" want="$3"
  : > "$TMP/dispatched"
  printf '%s' "$json" | cli codex >/dev/null 2>&1
  wait_for_log
  if [ -z "$want" ]; then
    [ ! -s "$TMP/dispatched" ] && ok "$label" || bad "$label: dispatched [$(cat "$TMP/dispatched")]"
  else
    [ "$(cat "$TMP/dispatched" 2>/dev/null)" = "$want" ] \
      && ok "$label" || bad "$label: wanted [$want] got [$(cat "$TMP/dispatched" 2>/dev/null)]"
  fi
}

grok_stdin() { # <label> <json-on-stdin> <expected-pattern|''>
  local label="$1" json="$2" want="$3"
  : > "$TMP/dispatched"
  printf '%s' "$json" | cli grok >/dev/null 2>&1
  wait_for_log
  if [ -z "$want" ]; then
    [ ! -s "$TMP/dispatched" ] && ok "$label" || bad "$label: dispatched [$(cat "$TMP/dispatched")]"
  else
    [ "$(cat "$TMP/dispatched" 2>/dev/null)" = "$want" ] \
      && ok "$label" || bad "$label: wanted [$want] got [$(cat "$TMP/dispatched" 2>/dev/null)]"
  fi
}

wait_for_log() {
  local i
  for i in $(seq 1 40); do
    [ -s "$TMP/dispatched" ] && break
    sleep 0.05
  done
}

# --- codex: JSON argv ------------------------------------------------------
collect "codex: agent-turn-complete argv JSON" p-done -- codex '{"type":"agent-turn-complete"}'
collect "codex: error argv JSON"               p-error -- codex '{"type":"error"}'
collect "codex: approval-required"             p-input -- codex '{"type":"approval-required"}'
collect "codex: session-configured"            p-start -- codex '{"type":"session-configured"}'
collect "codex: legacy bare name"              p-done -- codex agent-turn-complete
collect "codex: case/separator squashing"      p-start -- codex Session_Configured

# --- codex: JSON on stdin (hook-style) --------------------------------------
stdin_collect "codex: stdin hook_event_name Stop"   '{"hook_event_name":"Stop"}' p-done
stdin_collect "codex: stdin unknown event ignored"  '{"hook_event_name":"UserPromptSubmit"}' ''

# --- codex: unknown stays silent --------------------------------------------
expect_ignore "codex: unknown argv event ignored" -- codex '{"type":"mystery"}'
expect_ignore "codex: no input ignored" -- codex

# --- gemini (argv event names) ----------------------------------------------
collect "gemini: Stop"          p-done  -- gemini Stop
collect "gemini: TurnComplete"  p-done  -- gemini TurnComplete
collect "gemini: Notification"  p-input -- gemini Notification
collect "gemini: SessionStart"  p-start -- gemini SessionStart
expect_ignore "gemini: unknown event ignored" -- gemini SomethingElse

# --- cursor ------------------------------------------------------------------
collect "cursor: stop"                  p-done -- cursor stop
collect "cursor: beforeSubmitPrompt"    p-ack  -- cursor beforeSubmitPrompt
collect "cursor: beforeShellExecution"  p-ack  -- cursor beforeShellExecution
expect_ignore "cursor: afterFileEdit too noisy (silent)" -- cursor afterFileEdit
expect_ignore "cursor: unknown event ignored" -- cursor mystery

# --- grok (stdin JSON, camelCase hookEventName) -------------------------------
grok_stdin "grok: stop"          '{"hookEventName":"stop"}' p-done
grok_stdin "grok: notification"  '{"hookEventName":"notification"}' p-input
grok_stdin "grok: session_start" '{"hookEventName":"session_start"}' p-start
grok_stdin "grok: unknown ignored" '{"hookEventName":"mystery"}' ''

# --- adapters/*.sh shims still route (compat path) ---------------------------
mkdir -p "$H/.peon-poke/bin"
cp "$REPO/peon-poke" "$H/.peon-poke/bin/peon-poke"
chmod +x "$H/.peon-poke/bin/peon-poke"
: > "$TMP/dispatched"
env HOME="$H" POKE_DIR="$H/.peon-poke" POKE_BIN="$TMP/stub-poke" \
  bash "$REPO/adapters/gemini.sh" Stop >/dev/null 2>&1
wait_for_log
[ "$(cat "$TMP/dispatched" 2>/dev/null)" = "p-done" ] \
  && ok "adapters/gemini.sh shim routes through the CLI" \
  || bad "gemini shim: got [$(cat "$TMP/dispatched" 2>/dev/null)]"

echo "----"
echo "adapters: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
