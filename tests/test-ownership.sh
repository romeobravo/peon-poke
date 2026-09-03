#!/bin/bash
# test-ownership.sh — file ownership + backup stability (setup/uninstall).
#
# - a foreign peon-poke.ts in an extension dir is never clobbered by
#   setup and never deleted by uninstall
# - a user-modified copy of OUR extension is refreshed, but one stable
#   .peon-poke-bak preserves the modified version
# - settings.json / config.toml .peon-poke-bak is the ORIGINAL rollback
#   point: re-running setup or uninstall must never overwrite it
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"

ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

run_setup()    { env HOME="$H" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1; }
run_uninstall(){ env HOME="$H" POKE_DIR="$H/.peon-poke" bash "$REPO/uninstall.sh" "$@" >>"$TMP/uninstall.log" 2>&1; }
fresh() { rm -rf "$H"; mkdir -p "$H/.codex" "$H/.pi/agent/extensions"; }

# ------------------------------------------------- foreign extension file ---
fresh
cat > "$H/.pi/agent/extensions/peon-poke.ts" <<'EOF'
// my own extension that happens to be named peon-poke.ts
export default function (pi: { on: (e: string, f: () => void) => void }) {
  pi.on("agent_settled", () => console.log("mine"));
}
EOF
cp "$H/.pi/agent/extensions/peon-poke.ts" "$TMP/foreign-original.ts"
run_setup
cmp -s "$TMP/foreign-original.ts" "$H/.pi/agent/extensions/peon-poke.ts" \
  && ok "setup: foreign extension file left untouched" || bad "setup: foreign file clobbered"
run_uninstall
[ -f "$H/.pi/agent/extensions/peon-poke.ts" ] \
  && ok "uninstall: foreign extension file survives" || bad "uninstall: foreign file deleted"

# --------------------------------------- user-modified copy of OUR file -----
fresh
cat > "$H/.pi/agent/extensions/peon-poke.ts" <<'EOF'
/**
 * peon-poke — pi (and oh-my-pi) extension
 * (user-tweaked copy: louder pattern)
 */
export default function (pi: { on: (e: string, f: () => void) => void }) {
  pi.on("agent_settled", () => console.log("LOUDER"));
}
EOF
run_setup
head -n 3 "$H/.pi/agent/extensions/peon-poke.ts" | grep -q "Managed by peon-poke-setup" \
  && ok "setup: recognized-modified extension refreshed to current" \
  || bad "setup: our extension not refreshed"
[ -f "$H/.pi/agent/extensions/peon-poke.ts.peon-poke-bak" ] \
  && grep -q "LOUDER" "$H/.pi/agent/extensions/peon-poke.ts.peon-poke-bak" \
  && ok "setup: modified copy preserved as stable .peon-poke-bak" \
  || bad "setup: modified copy lost"
# third run: no bak churn (already exists, file now identical anyway)
run_setup
[ "$(ls "$H/.pi/agent/extensions/" | wc -l | tr -d ' ')" = 2 ] \
  && ok "setup: re-run creates no extra backups" || bad "setup: backup churn"

# ------------------------------------------------ original settings backup ---
fresh
cat > "$H/.claude-settings-src.json" <<'EOF'
{"model": "opus"}
EOF
mkdir -p "$H/.claude"
cp "$H/.claude-settings-src.json" "$H/.claude/settings.json"
run_setup
cmp -s "$H/.claude-settings-src.json" "$H/.claude/settings.json.peon-poke-bak" \
  && ok "setup: settings.json backup is the pre-peon-poke original" || bad "setup: backup is not the original"
# user adds a key, runs setup again: backup must stay the ORIGINAL
python3 - "$H/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
cfg = json.load(open(p)); cfg["theme"] = "dark"
json.dump(cfg, open(p, "w"), indent=2)
PY
run_setup
cmp -s "$H/.claude-settings-src.json" "$H/.claude/settings.json.peon-poke-bak" \
  && ok "setup: re-run does NOT overwrite original settings backup" \
  || bad "setup: re-run destroyed original settings backup"
grep -q '"theme": "dark"' "$H/.claude/settings.json" \
  && ok "setup: user keys survive re-registration" || bad "setup: user keys lost"

# -------------------------------------------------- original codex backup ---
fresh
printf 'model = "gpt-5"\n' > "$H/.codex/config.toml"
run_setup
[ -f "$H/.codex/config.toml.peon-poke-bak" ] && grep -q 'notify' "$H/.codex/config.toml.peon-poke-bak" \
  && bad "codex backup already contains our notify" || ok "setup: codex backup is the original"
run_uninstall
grep -q 'notify' "$H/.codex/config.toml.peon-poke-bak" \
  && bad "uninstall overwrote the original codex backup" \
  || ok "uninstall keeps the original codex backup intact"
cmp -s <(printf 'model = "gpt-5"\n') "$H/.codex/config.toml" \
  && ok "uninstall: codex config restored to original content" || bad "uninstall: codex config not restored"

echo "----"
echo "ownership: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
