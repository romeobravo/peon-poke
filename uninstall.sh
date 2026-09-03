#!/bin/bash
# peon-poke uninstaller: removes hook registrations and installed files.
#
# Installed as `peon-poke-uninstall` on your PATH by peon-poke-setup
# (fallback: bash ~/.peon-poke/uninstall.sh). Pass --purge to also remove
# ~/.config/peon-poke/config.json.
#
# Deletion safety: targets are canonicalized and checked against a
# refuse-list (/, $HOME, empty) and must look like a peon-poke install.
# A deliberately custom install location can be forced with
# POKE_UNSAFE_RM=1 — know what you are doing.
set -euo pipefail

INSTALL_DIR="${POKE_DIR:-$HOME/.peon-poke}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/peon-poke"

info() { printf "> %s\n" "$*"; }
warn() { printf "! %s\n" "$*" >&2; }

# ---------------------------------------------------------------------------
# Guarded removal. Usage: safe_rm <dir> <what-this-must-be>
# Refuses /, $HOME, empty and non-canonical paths, and anything that does
# not structurally look like a peon-poke install (poke.sh / bin/poke /
# adapters/ inside, or a path ending in peon-poke). Override: POKE_UNSAFE_RM=1.
# ---------------------------------------------------------------------------
safe_rm() {
  local dir="$1" real real_parent home_real
  [ -n "$dir" ] || { warn "refusing to remove: empty path"; return 1; }

  # Canonicalize (resolve symlinks, trailing slashes, ..) — /tmp vs /private/tmp
  real_parent="$(cd "$(dirname "$dir")" 2>/dev/null && pwd -P)" || {
    warn "refusing to remove '$dir': parent directory does not exist"
    return 1
  }
  real="$real_parent/$(basename "$dir")"
  home_real="$(cd "$HOME" 2>/dev/null && pwd -P)"

  case "$real" in
    /|"$home_real"|"$home_real"/)
      warn "refusing to remove '$real' (refuse-list: / and \$HOME)"
      return 1 ;;
  esac

  local looks_like_install=0 suffix_ok=0
  [ -f "$real/poke.sh" ] || [ -f "$real/bin/poke" ] || [ -d "$real/adapters" ] && looks_like_install=1
  case "$real" in
    *.peon-poke|*/peon-poke) suffix_ok=1 ;;
  esac

  if [ "$looks_like_install" = 1 ] || [ "$suffix_ok" = 1 ]; then
    rm -rf "$real" && info "Removed $real"
    return 0
  fi

  if [ "${POKE_UNSAFE_RM:-}" = 1 ]; then
    warn "POKE_UNSAFE_RM=1 set: removing '$real' despite failing safety checks"
    rm -rf "$real" && info "Removed $real"
    return 0
  fi

  warn "refusing to remove '$real': not recognizable as a peon-poke install"
  warn "(custom install dir? re-run with POKE_UNSAFE_RM=1 if you are sure)"
  return 1
}

# --- Claude Code: drop our hook entries (backup + atomic rewrite) ---
if [ -f "$HOME/.claude/settings.json" ] && command -v python3 >/dev/null; then
  if python3 - <<'PY'
import json, os, shutil, sys, tempfile

path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception:
    sys.stderr.write("peon-poke: cannot parse ~/.claude/settings.json — left untouched\n")
    raise SystemExit(1)

hooks = cfg.get("hooks", {})
removed = 0
for event, entries in list(hooks.items()):
    kept = [e for e in entries if "peon-poke" not in json.dumps(e)]
    removed += len(entries) - len(kept)
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]
if not removed:
    raise SystemExit(3)  # nothing of ours in there — leave the file untouched

# stable original backup: never overwrite an existing .peon-poke-bak
if not os.path.exists(path + ".peon-poke-bak"):
    shutil.copy2(path, path + ".peon-poke-bak")
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings.json.")
with os.fdopen(fd, "w") as f:
    json.dump(cfg, f, indent=2)
os.replace(tmp, path)  # atomic
PY
  then
    info "Claude Code hooks removed"
  else
    warn "No peon-poke hooks found in Claude settings (left untouched)"
  fi
fi

# --- Codex: remove ONLY the managed notify we added (backup + atomic) ---
CODEX_TOML="$HOME/.codex/config.toml"
if [ -f "$CODEX_TOML" ] && command -v python3 >/dev/null; then
  if python3 - "$CODEX_TOML" "$INSTALL_DIR" <<'PY'
import json, os, re, shutil, sys, tempfile

path, install_dir = sys.argv[1], sys.argv[2]
MARKER = "# peon-poke (managed — remove to uninstall)"
escaped = json.dumps(os.path.join(install_dir, "adapters", "codex.sh"))[1:-1]
default_escaped = json.dumps(os.path.expanduser("~/.peon-poke/adapters/codex.sh"))[1:-1]

def is_our_notify(line):
    # Structurally a `notify = [...]` assignment whose value points at a
    # peon-poke codex adapter (current or default install dir).
    body = line.split("#", 1)[0]
    if not re.match(r"^\s*notify\s*=\s*\[", body):
        return False
    return escaped in line or default_escaped in line

lines = open(path).readlines()
out, i, removed = [], 0, False
seams = []  # out-index where each managed block was lifted
while i < len(lines):
    l = lines[i].rstrip("\n")
    if l.strip() == MARKER and i + 1 < len(lines) and is_our_notify(lines[i + 1]):
        seams.append(len(out)); i += 2; removed = True; continue  # block
    if is_our_notify(l):
        seams.append(len(out)); i += 1; removed = True; continue   # bare line
    out.append(lines[i]); i += 1

# Each lifted block leaves its separator blank line behind — drop one per seam.
for s in sorted(set(seams), reverse=True):
    if 0 < s <= len(out) and out[s - 1].strip() == "":
        del out[s - 1]
    elif s < len(out) and out[s].strip() == "":
        del out[s]

if not removed:
    if any("peon-poke" in l for l in lines):
        sys.stderr.write("peon-poke: mentions of peon-poke found in " + path
                         + " but no managed notify — file left untouched\n")
        raise SystemExit(1)
    raise SystemExit(1)  # nothing to do; stay quiet

# Tidy: drop a blank line left directly before EOF by block removal
while out and out[-1].strip() == "":
    out.pop()
if out:
    out[-1] = out[-1].rstrip("\n") + "\n"

# stable original backup: never overwrite an existing .peon-poke-bak
if not os.path.exists(path + ".peon-poke-bak"):
    shutil.copy2(path, path + ".peon-poke-bak")
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".config.toml.")
with os.fdopen(fd, "w") as f:
    f.writelines(out)
os.replace(tmp, path)  # atomic
PY
  then
    info "Codex notify removed"
  else
    warn "No managed Codex notify found (left untouched)"
  fi
fi

# --- pi / omp extensions (only files we own; foreign files survive) ---
for f in "$HOME/.pi/agent/extensions/peon-poke.ts" "$HOME/.omp/agent/extensions/peon-poke.ts"; do
  if [ -f "$f" ]; then
    if head -n 8 "$f" | grep -q 'peon-poke-setup\|pi (and oh-my-pi) extension'; then
      rm -f "$f" "$f.peon-poke-bak" && info "Removed $f"
    else
      warn "$f is not recognized as ours — left untouched"
    fi
  fi
done

# --- uninstall command symlink (best effort) ---
for d in "$HOME/.local/bin" "$HOME/bin" /usr/local/bin; do
  if [ -L "$d/peon-poke-uninstall" ] \
     && readlink "$d/peon-poke-uninstall" 2>/dev/null | grep -q "peon-poke/bin/peon-poke-uninstall"; then
    rm -f "$d/peon-poke-uninstall" && info "Removed $d/peon-poke-uninstall"
  fi
done

# --- installed files (config kept unless --purge) ---
safe_rm "$INSTALL_DIR"
if [ "${1:-}" = "--purge" ]; then
  safe_rm "$CONFIG_DIR"
else
  info "Kept $CONFIG_DIR/config.json (use --purge to remove)"
fi
