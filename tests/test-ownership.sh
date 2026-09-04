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

# A fake ~/.local/bin is PREPENDED to PATH: setup's uninstall-command
# loop takes the first writable on-PATH dir, so the fake one wins and
# the real /usr/local/bin is never reached — the rest of PATH (python
# discovery) stays intact.
run_setup()    { mkdir -p "$H/.local/bin"; env HOME="$H" PATH="$H/.local/bin:$PATH" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1; }
run_uninstall(){ env HOME="$H" POKE_DIR="$H/.peon-poke" bash "$REPO/uninstall.sh" "$@" >>"$TMP/uninstall.log" 2>&1; }
fresh() { rm -rf "$H"; mkdir -p "$H/.codex" "$H/.pi/agent/extensions" "$H/.config/opencode"; }

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

# ------------------------------------------- symlinked settings.json ---
# Writing through a symlink would silently modify its target — refuse.
fresh
mkdir -p "$H/.claude" "$H/elsewhere"
printf '{"model": "opus"}\n' > "$H/elsewhere/real-settings.json"
ln -s "$H/elsewhere/real-settings.json" "$H/.claude/settings.json"
run_setup
[ -L "$H/.claude/settings.json" ] \
  && ok "setup: symlinked settings.json not replaced" || bad "setup: replaced symlinked settings.json"
cmp -s <(printf '{"model": "opus"}\n') "$H/elsewhere/real-settings.json" \
  && ok "setup: settings.json symlink target untouched" || bad "setup: wrote through settings.json symlink"

# --------------------------------------------- symlinked extension file ---
fresh
mkdir -p "$H/.pi/agent/extensions" "$H/elsewhere"
printf '// foreign target\n' > "$H/elsewhere/target.ts"
ln -s "$H/elsewhere/target.ts" "$H/.pi/agent/extensions/peon-poke.ts"
run_setup
[ -L "$H/.pi/agent/extensions/peon-poke.ts" ] \
  && ok "setup: symlinked extension left as a symlink" || bad "setup: replaced symlinked extension"
cmp -s <(printf '// foreign target\n') "$H/elsewhere/target.ts" \
  && ok "setup: extension symlink target untouched" || bad "setup: wrote through extension symlink"

# --------------------------------- uninstall-command symlink ownership ---
# setup must never replace a foreign symlink, but must (re)create its own.
# Both command names (peon-poke, peon-poke-uninstall) point at the one CLI
# file; the uninstall subcommand is chosen by argv[0].
fresh; run_setup
[ -L "$H/.local/bin/peon-poke-uninstall" ] \
  && [ "$(readlink "$H/.local/bin/peon-poke-uninstall")" = "$H/.peon-poke/bin/peon-poke" ] \
  && ok "setup: uninstall command symlink points at the CLI" \
  || bad "setup: uninstall symlink missing or points elsewhere"
[ -L "$H/.local/bin/peon-poke" ] \
  && [ "$(readlink "$H/.local/bin/peon-poke")" = "$H/.peon-poke/bin/peon-poke" ] \
  && ok "setup: peon-poke command symlink points at the CLI" \
  || bad "setup: peon-poke symlink missing or points elsewhere"
rm -f "$H/.local/bin/peon-poke-uninstall" "$H/.local/bin/peon-poke"
ln -s "$H/bin/elsewhere-uninstall" "$H/.local/bin/peon-poke-uninstall"
ln -s "$H/bin/elsewhere" "$H/.local/bin/peon-poke"
run_setup
[ "$(readlink "$H/.local/bin/peon-poke-uninstall")" = "$H/bin/elsewhere-uninstall" ] \
  && ok "setup: foreign uninstall symlink not replaced" || bad "setup: replaced foreign uninstall symlink"
[ "$(readlink "$H/.local/bin/peon-poke")" = "$H/bin/elsewhere" ] \
  && ok "setup: foreign peon-poke symlink not replaced" || bad "setup: replaced foreign peon-poke symlink"

# ------------------- PATH links stay in the first dir on re-runs -------
# The first writable on-PATH dir wins — once our links exist there, a
# re-run must not "helpfully" add them to the next candidate dir too.
fresh
mkdir -p "$H/.local/bin" "$H/bin"
env HOME="$H" PATH="$H/.local/bin:$H/bin:$PATH" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1
env HOME="$H" PATH="$H/.local/bin:$H/bin:$PATH" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1
[ -L "$H/.local/bin/peon-poke" ] && [ ! -e "$H/bin/peon-poke" ] \
   && [ ! -e "$H/bin/peon-poke-uninstall" ] \
   && ok "setup: PATH links stay in the first candidate dir across re-runs" \
   || bad "setup: PATH links spread to a second candidate dir"

# --------------- setup re-run from the installed CLI (self-heal) -------
# The documented healing path: `peon-poke setup` via the installed CLI
# (or its PATH symlink) must re-register hooks in place, not demand a
# repo checkout next to the binary.
fresh
mkdir -p "$H/.claude" "$H/.local/bin"
run_setup
id1="$(sed -n 's/^install_id=//p' "$H/.peon-poke/.peon-poke-install")"
env HOME="$H" PATH="$H/.local/bin:$PATH" "$H/.peon-poke/bin/peon-poke" setup >>"$TMP/setup.log" 2>&1
rc=$?
id2="$(sed -n 's/^install_id=//p' "$H/.peon-poke/.peon-poke-install")"
if [ "$rc" = 0 ] \
   && [ "$(grep -c ' dispatch ' "$H/.claude/settings.json")" = 3 ] \
   && ! grep -q "not found or not executable" "$TMP/setup.log" \
   && [ "$id1" = "$id2" ]; then
  ok "setup: re-run from the installed CLI heals in place"
else
  bad "setup: installed-CLI re-run broken (rc=$rc)"
fi
# version survives without a VERSION file next to the installed CLI
v="$(sed -n 's/^version=//p' "$H/.peon-poke/.peon-poke-install")"
case "$($H/.peon-poke/bin/peon-poke --version)" in
  *" unknown"|"") bad "installed CLI version: '$v' / --version broken" ;;
  *) ok "installed CLI reports its version without a VERSION file" ;;
esac

# ---------------- install dir with spaces: hook ownership round-trip ---
# shlex.join single-quotes such paths; registration must recognize our
# own single-quoted shape (no duplicate entries on re-run) and uninstall
# must remove them again.
fresh
mkdir -p "$H/.claude" "$H/.local/bin"
SPACED="$H/My Tools/.peon-poke"
env HOME="$H" POKE_DIR="$SPACED" PATH="$H/.local/bin:$PATH" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1
env HOME="$H" POKE_DIR="$SPACED" PATH="$H/.local/bin:$PATH" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1
n="$(grep -c ' dispatch ' "$H/.claude/settings.json")"
[ "$n" = 3 ] && ok "spaced POKE_DIR: re-run does not duplicate hooks" \
  || bad "spaced POKE_DIR: $n hook commands after two setups (want 3)"
env HOME="$H" POKE_DIR="$SPACED" bash "$REPO/uninstall.sh" >>"$TMP/uninstall.log" 2>&1
! grep -q ' dispatch ' "$H/.claude/settings.json" \
  && ok "spaced POKE_DIR: uninstall removes all our hooks" \
  || bad "spaced POKE_DIR: uninstall left our hooks behind"

# --------------------- user hook mentioning peon-poke: exact ownership ---
# Registration skips only entries that are EXACTLY ours; a user's own
# hook that merely mentions peon-poke must survive setup and uninstall.
fresh
mkdir -p "$H/.claude"
cat > "$H/.claude/settings.json" <<EOF
{"hooks": {"Stop": [
  {"matcher": "", "hooks": [{"type": "command", "command": "bash $H/tools/my-peon-poke-wrapper.sh"}]}
]}}
EOF
run_setup
grep -q 'my-peon-poke-wrapper.sh' "$H/.claude/settings.json" \
  && ok "setup: user's peon-poke-mentioning hook preserved" || bad "setup: dropped user's peon-poke hook"
grep -Fq 'peon-poke dispatch task.complete' "$H/.claude/settings.json" \
  && ok "setup: our hook registered alongside the user's" || bad "setup: our hook not registered (skipped by loose match?)"
run_uninstall
grep -q 'my-peon-poke-wrapper.sh' "$H/.claude/settings.json" \
  && ok "uninstall: user's peon-poke-mentioning hook preserved" || bad "uninstall: deleted user's peon-poke hook"
grep -Fq 'peon-poke dispatch task.complete' "$H/.claude/settings.json" \
  && bad "uninstall: our hook left behind" || ok "uninstall: our hook removed"

# ------------------- user-modified extension restored on uninstall ---
# setup saved a .peon-poke-bak of the user's customized copy — uninstall
# restores their version instead of destroying both.
fresh
cat > "$H/.pi/agent/extensions/peon-poke.ts" <<'EOF'
/**
 * peon-poke — pi (and oh-my-pi) extension
 * (user-tweaked copy)
 */
export default function (pi: { on: (e: string, f: () => void) => void }) {
  pi.on("agent_settled", () => console.log("MINE"))
}
EOF
run_setup
grep -q MINE "$H/.pi/agent/extensions/peon-poke.ts.peon-poke-bak" \
  && ok "setup: user customization saved to .peon-poke-bak" || bad "setup: user customization not backed up"
run_uninstall
grep -q MINE "$H/.pi/agent/extensions/peon-poke.ts" \
  && ok "uninstall: user-modified extension restored from .peon-poke-bak" \
  || bad "uninstall: user customization lost"
[ ! -e "$H/.pi/agent/extensions/peon-poke.ts.peon-poke-bak" ] \
  && ok "uninstall: restore consumed the .peon-poke-bak" || bad "uninstall: stale .peon-poke-bak left behind"

# ------------------------------------------------- opencode plugin -------
# foreign plugin file must survive setup AND uninstall
fresh
mkdir -p "$H/.config/opencode/plugin"
cat > "$H/.config/opencode/plugin/peon-poke.ts" <<'EOF'
// my own plugin that happens to be named peon-poke.ts
export const Mine = async () => ({})
EOF
cp "$H/.config/opencode/plugin/peon-poke.ts" "$TMP/oc-foreign.ts"
run_setup
cmp -s "$TMP/oc-foreign.ts" "$H/.config/opencode/plugin/peon-poke.ts" \
  && ok "setup: foreign opencode plugin left untouched" || bad "setup: foreign opencode plugin clobbered"
run_uninstall
[ -f "$H/.config/opencode/plugin/peon-poke.ts" ] \
  && ok "uninstall: foreign opencode plugin survives" || bad "uninstall: foreign opencode plugin deleted"

# ours: installed by setup, removed by uninstall (dir kept — opencode owns it)
fresh
run_setup
head -n 3 "$H/.config/opencode/plugin/peon-poke.ts" | grep -q "Managed by peon-poke-setup" \
  && ok "setup: opencode plugin installed with marker" || bad "setup: opencode plugin not installed"
run_uninstall
[ ! -e "$H/.config/opencode/plugin/peon-poke.ts" ] \
  && ok "uninstall: our opencode plugin removed" || bad "uninstall: opencode plugin not removed"
[ -d "$H/.config/opencode/plugin" ] \
  && ok "uninstall: opencode plugin directory kept (opencode owns it)" \
  || bad "uninstall: opencode plugin directory deleted"

# opencode not detected -> skipped
fresh; rm -rf "$H/.config/opencode"
run_setup
grep -q "OpenCode not detected" "$TMP/setup.log" \
  && ok "setup: opencode skipped when not installed" || bad "setup: opencode not skipped when absent"

# XDG_CONFIG_HOME honored
fresh; rm -rf "$H/.config/opencode"; mkdir -p "$H/xdg/opencode" "$H/.local/bin"
env HOME="$H" XDG_CONFIG_HOME="$H/xdg" PATH="$H/.local/bin:$PATH" bash "$REPO/peon-poke-setup" >>"$TMP/setup.log" 2>&1
[ -f "$H/xdg/opencode/plugin/peon-poke.ts" ] \
  && ok "setup: XDG_CONFIG_HOME honored for opencode plugin" || bad "XDG_CONFIG_HOME not honored"

echo "----"
echo "ownership: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
