#!/bin/bash
# test-uninstall.sh — destructive-safety tests for uninstall.sh using a
# fake HOME (never touches the real one). Covers: exact managed-block
# removal, preservation of user notes/values, rm -rf guards, --purge,
# and the override escape hatch.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"

ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

run_uninstall() { env HOME="$H" POKE_DIR="$H/.peon-poke" bash "$REPO/uninstall.sh" "$@" ; }

fresh() { # fresh [codex-toml-content-file]
  rm -rf "$H"; mkdir -p "$H/.codex"
  [ -n "${1:-}" ] && cp "$1" "$H/.codex/config.toml"
  # pretend a full install exists (same shape peon-poke-setup creates)
  mkdir -p "$H/.peon-poke/bin" "$H/.peon-poke/adapters" "$H/.peon-poke/plugins/pi"
  echo "#!/bin/bash" > "$H/.peon-poke/poke.sh"
}

# ------------------------------------------- user note must NOT be eaten ---
cat > "$TMP/user-note.toml" <<'EOF'
model = "gpt-5"

# peon-poke is useful; this is a user note
approval_policy = "on-request"

[tui]
notifications = true
EOF
fresh "$TMP/user-note.toml"; run_uninstall >/dev/null 2>&1
cmp -s "$TMP/user-note.toml" "$H/.codex/config.toml" \
  && ok "user note + following line preserved byte-exactly" \
  || bad "user note case modified the file"
[ ! -f "$H/.codex/config.toml.peon-poke-bak" ] \
  && ok "untouched file: no backup churn" || bad "untouched file: wrote backup anyway"

# ------------------------------------------------ managed block removal ---
cat > "$TMP/managed.toml" <<'EOF'
model = "gpt-5"

# peon-poke (managed — remove to uninstall)
notify = ["bash", "PLACEHOLDER/adapters/codex.sh"]

[tui]
notifications = true
EOF
sed "s|PLACEHOLDER|$H/.peon-poke|" "$TMP/managed.toml" > "$TMP/managed-filled.toml"
fresh "$TMP/managed-filled.toml"; run_uninstall >/dev/null 2>&1
printf 'model = "gpt-5"\n\n[tui]\nnotifications = true\n' | cmp -s - "$H/.codex/config.toml" \
  && ok "managed block removed, rest byte-exact" || { bad "managed block removal changed file"; cat "$H/.codex/config.toml"; }
[ -f "$H/.codex/config.toml.peon-poke-bak" ] \
  && ok "backup written before codex config rewrite" || bad "no backup for codex rewrite"

# --------------------------------------------------------- POKE_DIR=$HOME ---
fresh
OUT="$(env HOME="$H" POKE_DIR="$H" bash "$REPO/uninstall.sh" 2>&1 || true)"
echo "$OUT" | grep -q "refusing to remove" && ok "POKE_DIR=\$HOME refused" || bad "POKE_DIR=\$HOME not refused"
[ -d "$H/.codex" ] && ok "HOME survived POKE_DIR=\$HOME" || bad "HOME was deleted!"

# ------------------------------------------------------- canonical $HOME ---
# /tmp -> /private/tmp symlink must not bypass the refuse-list
OUT="$(env HOME="$H" POKE_DIR="${TMP}/home" bash "$REPO/uninstall.sh" 2>&1 || true)"
echo "$OUT" | grep -q "refusing" && ok "canonicalized \$HOME refused" || bad "canonical \$HOME not refused"

# -------------------------------------------------------- unrelated dir ---
mkdir -p "$H/precious"; echo data > "$H/precious/file"
OUT="$(env HOME="$H" POKE_DIR="$H/precious" bash "$REPO/uninstall.sh" 2>&1 || true)"
echo "$OUT" | grep -q "refusing" && ok "non-install dir refused" || bad "non-install dir not refused"
[ -f "$H/precious/file" ] && ok "non-install dir contents survived" || bad "non-install dir deleted"

# -------------------------------------------------- override escape hatch ---
OUT="$(env HOME="$H" POKE_DIR="$H/precious" POKE_UNSAFE_RM=1 bash "$REPO/uninstall.sh" 2>&1 || true)"
[ ! -d "$H/precious" ] && ok "POKE_UNSAFE_RM=1 override removes" || bad "override did not remove"

# ------------------------------------------------------------ --purge -----
fresh
mkdir -p "$H/.config/peon-poke"; echo '{}' > "$H/.config/peon-poke/config.json"
run_uninstall >/dev/null 2>&1
[ -f "$H/.config/peon-poke/config.json" ] && ok "config kept without --purge" || bad "config removed without --purge"
fresh
mkdir -p "$H/.config/peon-poke"; echo '{}' > "$H/.config/peon-poke/config.json"
run_uninstall --purge >/dev/null 2>&1
[ ! -d "$H/.config/peon-poke" ] && ok "config removed with --purge" || bad "--purge did not remove config"

# ------------------------------------------------ normal removal happens ---
fresh
run_uninstall >/dev/null 2>&1
[ ! -d "$H/.peon-poke" ] && ok "install dir removed in normal case" || bad "install dir not removed"

echo "----"
echo "uninstall: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
