# Plan: Python CLI control plane for peon-poke

Status: implemented on branch `python-cli`. Source analysis doc: `/tmp/python-cli.md`.

## Goal

Replace the bash *logic* (dispatch, setup, uninstall, adapters) with a single
Python CLI, while keeping the C actuator core, the TypeScript plugins, and
every existing entry-point name working. "Reducing the dependency on bash"
means: no bash ever makes a decision — the few remaining `.sh` files are
2–5 line `exec` trampolines with zero logic in them.

## Architecture

```
agent hook / plugin / user
        │
        ▼
peon-poke (single-file Python CLI, ~/.peon-poke/bin/peon-poke)
  ├── dispatch <category|pattern>     ← replaces poke.sh core
  ├── play <pattern>                  ← alias of dispatch
  ├── codex | gemini | cursor | grok  ← event adapters (tables, no bash)
  ├── setup                           ← replaces peon-poke-setup core
  ├── uninstall [--purge]             ← replaces uninstall.sh core
  └── doctor                          ← new: health/config report
        │
        ▼
bin/poke (C, unchanged)  →  MultitouchSupport.framework
```

pi / OpenCode plugins stay TypeScript but spawn `bin/peon-poke` directly
instead of `bash poke.sh`.

## File map

| Path | Before | After |
|---|---|---|
| `peon-poke` | — | **new**: the whole control plane (python3.8+, stdlib only) |
| `peon-poke-setup` | bash + embedded python (~400 lines) | 5-line `sh` shim → `peon-poke setup` |
| `uninstall.sh` | bash + embedded python (~270 lines) | 5-line `sh` shim → `peon-poke uninstall` |
| `poke.sh` | bash + embedded python dispatcher | 5-line `sh` shim → `peon-poke dispatch` |
| `adapters/codex.sh` | bash + embedded python | **deleted** — Codex notify points straight at the CLI |
| `adapters/{gemini,cursor,grok}.sh` | bash event tables | 2-line `sh` shims → `peon-poke <agent>` |
| `plugins/pi/poke.ts`, `plugins/opencode/peon-poke.ts` | spawn `bash poke.sh` | spawn `bin/peon-poke` directly |
| `install.sh`, `install-remote.sh`, `scripts/*.sh` | bash | unchanged (build bootstrap + trust boundary; plan doc says keep small) |

Shim resolution: repo checkout → sibling `peon-poke`; installed runtime →
`${POKE_DIR:-~/.peon-poke}/bin/peon-poke`. Adapters only ever run installed,
so they use the install path directly.

## Compatibility & ownership rules

1. **Python version: 3.8+** (stock macOS python3 works; no tomllib required at
   import time — TOML edits are structurally validated, parse-validated only
   when tomllib exists). `shlex.join` needs 3.8, nothing newer.
2. **Ownership markers unchanged**: `.peon-poke-install` / `.peon-poke-config`
   with the same `app/kind/install_id/version` format and UUID identity —
   `safe_rm` semantics (refuse-list, kind-strict markers, `POKE_UNSAFE_RM`)
   ported verbatim. Deletion still never authorized by name/shape.
3. **Claude hooks — two shapes, both owned**:
   - old: `bash ".../poke.sh" <category>` (registered by ≤0.6.x)
   - new: `".../bin/peon-poke" dispatch <category>` (built with `shlex.join`,
     safe for spaces/quotes)
   Setup heals old→new (removes old-shape entries, registers new, exactly one
   per event); uninstall removes both. User hooks that merely mention
   peon-poke still survive everything.
4. **Codex TOML — two shapes, both owned**:
   - old: `notify = ["bash", ".../adapters/codex.sh"]` (+ marker comment)
   - new: `notify = [".../bin/peon-poke", "codex"]`
   Same surgical line editor (comment-stripped body decides ownership, user's
   top-level notify wins, healing of legacy mis-scoped/duplicate blocks,
   stable `.peon-poke-bak`, atomic write, tomllib validation when available).
5. **PATH commands**: `peon-poke` and `peon-poke-uninstall` symlinks → the one
   CLI file; the uninstall subcommand is selected via `argv[0]` basename, so
   no launcher script is needed. Old links to the ≤0.6.x
   `bin/peon-poke-uninstall` launcher are refreshed (they point exactly at our
   own target) or left functional; uninstall removes links whose target is
   exactly ours.
6. **Env contract preserved**: `POKE_DIR`, `POKE_BIN`, `POKE_CONFIG`,
   `XDG_CONFIG_HOME`, `POKE_QUIET`, `POKE_PATTERN`, `PEON_POKE_SRC`.
7. **Dispatch invariants preserved**: always exit 0, fire detached
   (`start_new_session`), fully quiet, never blocks the host agent.

## What is deliberately NOT in this change

- No installation-receipt JSON / hash ledger (existing markers + exact-shape
  ownership already cover the destructive paths and are heavily tested).
- No TOML writer dependency (`tomlkit`) — surgical editor stays.
- No bundled interpreter, no pip packaging, no Homebrew python dependency.
- No changes to `src/poke.c`, `Makefile`, `install.sh`, `install-remote.sh`
  logic, or release scripts.
- `~/.peon-poke/adapters/codex.sh` from old installs is left in place (dead
  but harmless until uninstall removes the dir); pruning stale files on
  upgrade is not worth the risk.

## Test plan

- `test-dispatch.sh` — unchanged (now exercises shim → CLI → stub end to end).
- `test-adapters.sh` (replaces `test-codex-adapter.sh`) — codex/gemini/cursor/
  grok subcommand dispatch matrix, incl. JSON argv, stdin JSON, legacy names,
  unknown-event silence.
- `test-codex-setup.sh` — updated shapes + new old-shape → new-shape migration
  case; all existing fixtures (empty/table-ending/user-notify/malformed/
  quoted-paths/idempotency/healing/comment-spoofing) retained.
- `test-uninstall.sh` — updated shapes (managed block removal for old + new
  notify shape, old Claude hook shape removal); all destructive-safety guards
  retained verbatim.
- `test-ownership.sh` — symlink/backup/hook-exact-ownership cases retained;
  PATH-link assertions updated to the new targets.
- `test-plugin*.sh` — stubs move from `poke.sh` to `bin/peon-poke`.
- `test-install-remote.sh` — `peon-poke` added to the expected payload set.
- CI: `python3 -m py_compile peon-poke` added to the syntax-check step.

## Release coupling (must happen at release time, not now)

- `SHA256SUMS` regenerated (this branch does it) and `install-remote.sh`
  allowlist + `scripts/sha256sums.sh` updated (this branch does it).
- **Homebrew tap formula** (`romeobravo/homebrew-tap`) must add `"peon-poke"`
  to `libexec.install` (and chmod 0755 it) in the same session the next
  release tag is cut — before that tag exists the old formula keeps working,
  after the tag exists the new formula is required. Not done on this branch
  to avoid breaking `brew install` against the v0.6.x tag.
- Per AGENTS.md: never push installer/runtime changes to `main` without
  cutting the release in the same session.
