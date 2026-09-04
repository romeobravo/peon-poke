#!/bin/bash
# test-uninstall.sh — destructive-safety tests for uninstall.sh using a
# fake HOME (never touches the real one). Covers: exact managed-block
# removal, preservation of user notes/values, rm -rf guards (ownership
# markers required — name/shape alone never authorizes), --purge, and the
# override escape hatch.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PASS=0 FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"
TEST_ID="11111111-2222-3333-4444-555555555555"

ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

run_uninstall() { env HOME="$H" POKE_DIR="$H/.peon-poke" bash "$REPO/uninstall.sh" "$@" ; }

stamp() { # stamp <dir> <marker> <kind> — write a marker like peon-poke-setup's
  mkdir -p "$1"
  printf 'app=peon-poke\nkind=%s\ninstall_id=%s\nversion=test\n' "$3" "$TEST_ID" > "$1/$2"
}

fresh() { # fresh [codex-toml-content-file]
  rm -rf "$H"; mkdir -p "$H/.codex"
  [ -n "${1:-}" ] && cp "$1" "$H/.codex/config.toml"
  # pretend a full install exists (same shape peon-poke-setup creates,
  # including its ownership marker)
  mkdir -p "$H/.peon-poke/bin" "$H/.peon-poke/adapters" "$H/.peon-poke/plugins/pi"
  echo "#!/bin/bash" > "$H/.peon-poke/poke.sh"
  stamp "$H/.peon-poke" ".peon-poke-install" install
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

# -------------------------- unrelated dir merely NAMED peon-poke (audit) ---
# Basename-only authorization must be gone: a path ending in /peon-poke
# with no ownership marker is somebody's data, not ours.
mkdir -p "$H/precious/peon-poke"; echo "only copy" > "$H/precious/peon-poke/only-copy.txt"
OUT="$(env HOME="$H" POKE_DIR="$H/precious/peon-poke" bash "$REPO/uninstall.sh" 2>&1 || true)"
echo "$OUT" | grep -q "refusing to remove" \
  && ok "unrelated dir ending in /peon-poke refused" || bad "basename-only authorization still present"
[ -f "$H/precious/peon-poke/only-copy.txt" ] \
  && ok "unrelated peon-poke-named dir survived" || bad "unrelated peon-poke-named dir deleted"

# same attack via --purge + XDG_CONFIG_HOME
OUT="$(env HOME="$H" XDG_CONFIG_HOME="$H/precious" POKE_DIR="$H/.peon-poke" bash "$REPO/uninstall.sh" --purge 2>&1 || true)"
echo "$OUT" | grep -q "refusing to remove" \
  && ok "--purge: unrelated dir ending in /peon-poke refused" || bad "--purge: basename-only authorization still present"
[ -f "$H/precious/peon-poke/only-copy.txt" ] \
  && ok "--purge: unrelated peon-poke-named dir survived" || bad "--purge: unrelated dir deleted"

# ------------------------------------- install-shaped but unmarked dir ---
# Contents that look like an install (poke.sh/bin/adapters) without a
# marker no longer authorize deletion — the marker is the only proof.
rm -rf "$H/legacy"; mkdir -p "$H/legacy/bin" "$H/legacy/adapters"; echo "#!/bin/bash" > "$H/legacy/poke.sh"
OUT="$(env HOME="$H" POKE_DIR="$H/legacy" bash "$REPO/uninstall.sh" 2>&1 || true)"
echo "$OUT" | grep -q "refusing to remove" \
  && ok "install-shaped dir without marker refused" || bad "structural heuristic still authorizes"
[ -d "$H/legacy" ] && ok "unmarked install-shaped dir survived" || bad "unmarked install-shaped dir deleted"

# ------------------------------------------- marker must be genuine -------
rm -rf "$H/phony"; mkdir -p "$H/phony/.peon-poke"; echo hello > "$H/phony/.peon-poke/.peon-poke-install"
OUT="$(env HOME="$H" POKE_DIR="$H/phony/.peon-poke" bash "$REPO/uninstall.sh" 2>&1 || true)"
echo "$OUT" | grep -q "refusing to remove" \
  && ok "garbage-marker dir refused" || bad "garbage marker accepted"
[ -d "$H/phony/.peon-poke" ] && ok "garbage-marker dir survived" || bad "garbage-marker dir deleted"

# wrong kind: a config marker must not authorize the runtime dir (and vice versa)
rm -rf "$H/swapped"; stamp "$H/swapped/.peon-poke" ".peon-poke-config" config
OUT="$(env HOME="$H" POKE_DIR="$H/swapped/.peon-poke" bash "$REPO/uninstall.sh" 2>&1 || true)"
echo "$OUT" | grep -q "refusing to remove" \
  && ok "cross-kind marker refused" || bad "cross-kind marker accepted"
[ -d "$H/swapped/.peon-poke" ] && ok "cross-kind marker dir survived" || bad "cross-kind marker dir deleted"

# -------------------------------------------------- override escape hatch ---
OUT="$(env HOME="$H" POKE_DIR="$H/precious" POKE_UNSAFE_RM=1 bash "$REPO/uninstall.sh" 2>&1 || true)"
[ ! -d "$H/precious" ] && ok "POKE_UNSAFE_RM=1 override removes" || bad "override did not remove"

# ------------------------------------------------------------ --purge -----
fresh
mkdir -p "$H/.config/peon-poke"; echo '{}' > "$H/.config/peon-poke/config.json"
stamp "$H/.config/peon-poke" ".peon-poke-config" config
run_uninstall >/dev/null 2>&1
[ -f "$H/.config/peon-poke/config.json" ] && ok "config kept without --purge" || bad "config removed without --purge"
fresh
mkdir -p "$H/.config/peon-poke"; echo '{}' > "$H/.config/peon-poke/config.json"
stamp "$H/.config/peon-poke" ".peon-poke-config" config
run_uninstall --purge >/dev/null 2>&1
[ ! -d "$H/.config/peon-poke" ] && ok "config removed with --purge" || bad "--purge did not remove config"
# config dir without a marker is not ours to delete
fresh
mkdir -p "$H/.config/peon-poke"; echo '{}' > "$H/.config/peon-poke/config.json"
run_uninstall --purge >/dev/null 2>&1
[ -f "$H/.config/peon-poke/config.json" ] \
  && ok "unmarked config dir survives --purge" || bad "--purge removed an unmarked config dir"

# ------------------------------------------------ normal removal happens ---
fresh
run_uninstall >/dev/null 2>&1
[ ! -d "$H/.peon-poke" ] && ok "install dir removed in normal case" || bad "install dir not removed"

# ------------------------------------- real setup/uninstall round-trip -----
# Markers written by the real peon-poke-setup must satisfy the real
# uninstaller, and the install identity must be stable across re-runs.
# A fake ~/.local/bin is prepended to PATH so setup's uninstall-command
# loop never reaches the real /usr/local/bin.
rm -rf "$H"; mkdir -p "$H/.codex" "$H/.pi/agent/extensions" "$H/.local/bin"
env HOME="$H" PATH="$H/.local/bin:$PATH" bash "$REPO/peon-poke-setup" >/dev/null 2>&1
ID1="$(sed -n 's/^install_id=//p' "$H/.peon-poke/.peon-poke-install")"
env HOME="$H" PATH="$H/.local/bin:$PATH" bash "$REPO/peon-poke-setup" >/dev/null 2>&1
ID2="$(sed -n 's/^install_id=//p' "$H/.peon-poke/.peon-poke-install")"
[ -n "$ID1" ] && [ "$ID1" = "$ID2" ] \
  && ok "setup: install identity stable across re-runs" || bad "setup: identity churned or empty"
run_uninstall --purge >/dev/null 2>&1
[ ! -d "$H/.peon-poke" ] \
  && ok "uninstall: setup-stamped install dir removed" || bad "uninstall: refused setup-stamped install dir"
[ ! -d "$H/.config/peon-poke" ] \
  && ok "uninstall: setup-stamped config dir purged" || bad "uninstall: refused setup-stamped config dir"

# ------------------------------- comment-spoofed foreign notify (audit) ---
# `notify = ["..."] # <our adapter path>` is the user's line: the path
# only appears in a comment, so uninstall must leave it alone.
cat > "$TMP/spoof.toml" <<EOF
notify = ["/usr/bin/true"] # $H/.peon-poke/adapters/codex.sh
model = "gpt-5"
EOF
fresh "$TMP/spoof.toml"; run_uninstall >/dev/null 2>&1
cmp -s "$TMP/spoof.toml" "$H/.codex/config.toml" \
  && ok "comment-spoofed foreign notify survives uninstall byte-identically" \
  || bad "uninstall removed a comment-spoofed foreign notify"

echo "----"
echo "uninstall: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
