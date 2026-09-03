# AGENTS.md — peon-poke

macOS trackpad haptic notifications for AI coding agents. Single-file C core (`src/poke.c`) + bash glue + one pi/oh-my-pi TypeScript extension. Runtime installs to `~/.peon-poke/`, config lives in `~/.config/peon-poke/config.json`.

## Post-mortems — lessons paid for during the original build

These bit us once; don't relearn them:

1. **macOS 26 broke every assumed MultitouchSupport signature.** Four drifts, all found empirically: `MTDeviceGetDeviceID` writes through an out-param (returning it segfaulted), `MTActuatorCreateFromDeviceID`'s `IOPropertyMatch` matches nothing (the actuator service is found via class `AppleActuatorDevice`), `MTActuatorCreate` is no longer exported (recovered by decoding the `BL` at the `mov x1,#0` / `bl` / `mov x20,x0` triple inside the exported function), and `MTActuatorOpen` returns `kern_return_t` (0 = success — treating it as `bool` inverts success/failure). **Rule: trust the disassembly on the running OS, not stale reverse-engineered headers or other projects' bindings.** lldb resolves shared-cache symbols only after `dlopen` — break on the symbol, then disassemble.
2. **`ret 0` is not "it worked."** Actuation IDs 15/16 returned success codes in testing but the user never felt them; they were removed. Community lore claimed 0–9 valid; firmware rejects 0 and 7–9 outright. **Rule: the valid ID set (currently 1–6) is empirical, per-firmware, and verified by human fingertips. When the user reports a pattern dead, remove it regardless of return codes.**
3. **A failed multi-edit is all-or-nothing — verify the survivors.** An edit batch that aborted on one non-matching `oldText` silently dropped the *critical* change (the default pattern stayed `chirp` while README, config, and release notes all claimed `fortune`). The build still passed; only firing the binary exposed it. **Rule: after any partially-failed edit or rename, `grep` for the expected new content everywhere — code, docs, config examples (`heart` survived in two README spots during the heartbeat rename).**
4. **Structural edits clipped a `for`-loop header** when three overlapping edits reorganized a function; the compiler caught it, but only because we rebuilt immediately. **Rule: restructuring = one precise edit per region, then `make` before anything else.**
5. **Direction bugs come from naming, not just code.** `rampup`/`rampdown` was confused twice: once as an encoding typo (`argv[1][4] == 'p'` matched neither word — index 4 of `rampup` is `u`), once as a semantic mislabel (a pattern named `slowdown` that speeds up). **Rule: name patterns by what the user feels, and verify the felt result by firing — never by rereading the gap table.**
6. **Two artifacts, one truth.** The repo and the live `~/.peon-poke/` install drift the moment you edit one. After touching `src/poke.c`, `poke.sh`, or the config schema: rebuild, `cp` into `~/.peon-poke/`, and fire through the dispatcher. Hook output is suppressed by design, so verify the detached child with `pgrep -fl bin/poke` — it shows the resolved pattern name and caught several would-be silent misroutes.
7. **Nothing fetched at install time may come from a mutable ref.** External review flagged that the curl installer pulled its payload from `main` — every push was a silent release. Fixed by resolving the latest release tag (plus `SHA256SUMS`). Keep it that way: new install-time files must be tag-served and manifest-verified, always.
8. **Verify repo state after `gh` mutations.** Visibility flipped unnoticed at one point; `gh repo view --json visibility` after operations that touch repo settings is cheap insurance.

## Editing hygiene for agents

- Shell scripts: `bash -n` after every edit, before any commit that ships them.
- Bulk renames (we did peon-boop → peon-poke): decide the identifier classes first. That rename moved app name, binary name, paths, and `BOOP_*`→`POKE_*` env vars — but deliberately kept the `boop` *pattern name* (`poke boop` is correct). A flat `sed s/boop/poke/g` would have corrupted pattern tables and gap lists.
- Config schema changes must be backward-tolerant: `poke.sh` treats `custom`, `strength`, and `enabled` as optional because users own `~/.config/peon-poke/config.json` and installs never overwrite it.

## Invariants — never break these

- `bin/poke` **always exits 0**, even on failure — hooks must never fail the host agent. Diagnostics go to stderr; `POKE_QUIET=1` silences them.
- Gap values are clamped to 0–10000 ms (`GAP_MAX_MS` in `play_sequence`): `usleep` takes an unsigned count, so an unclamped negative gap parks the process for ~71 minutes.
- `poke.sh` fires detached, quiet, and never blocks the calling agent.
- `peon-poke-setup` never clobbers `~/.claude/settings.json`: on parse failure it skips Claude registration and leaves the file byte-identical; otherwise it writes `settings.json.peon-poke-bak` before modifying. `config.json` is only created if missing, never overwritten.
- `install-remote.sh` verifies every fetched file against `SHA256SUMS` **before executing anything**, and hard-fails if the manifest is missing at the install base. The manifest also drives the fetch list — it must include `uninstall.sh` (setup copies it into `~/.peon-poke/` and installs the `peon-poke-uninstall` command) and the universal dist binary.

## Build & smoke test

```
make                 # clang -O2 -Wall — must stay warning-free
./bin/poke boop      # single pulse (fires real haptics)
./bin/poke -5,-5,-5  # must return instantly (gap clamping)
./bin/poke nosuch    # usage on stderr, exit 0
```

## Test suite

`tests/run-all.sh` covers the Codex adapter dispatch matrix, the TOML-aware
setup fixtures (empty / table-ending / existing-notify / malformed /
quoted-path configs), and the uninstaller's destructive-safety guards —
all against isolated fake HOMEs. Run it before any release and after any
change to `adapters/`, `peon-poke-setup`, or `uninstall.sh`:

```
bash tests/run-all.sh
```

## dist binary

`dist/poke-darwin-universal` (arm64 + x86_64, `-mmacosx-version-min=12.0`) is committed to git. Homebrew builds from source, but the curl installer ships this binary — **rebuild and refresh it after every `src/poke.c` change**:

```
make dist
```

Never ship a binary built without the deployment target — it silently inherits the build machine's macOS (that's how we once shipped a macOS-26-only binary while claiming 12+ support).

## SHA256SUMS

`install-remote.sh` fetches exactly the files listed in `SHA256SUMS` and verifies each one. Whenever you touch `install.sh`, `peon-poke-setup`, `uninstall.sh`, `poke.sh`, `config.json`, `dist/poke-darwin-universal`, `plugins/pi/*.ts`, or `adapters/*.sh`, regenerate and commit the manifest:

```
scripts/sha256sums.sh
```

## Releases

```
scripts/release.sh <X.Y.Z> ["commit message"]
```

Full flow: preflight checks → rebuild → refresh `dist/` → regenerate `SHA256SUMS` → bump `VERSION` → commit → tag `vX.Y.Z` → push main + tag → `gh release create` → bump the Homebrew tap (`scripts/brew-bump.sh`).

**Ordering matters:** the remote installer resolves the latest GitHub release and hard-requires `SHA256SUMS` at that tag. Never push installer/runtime changes to `main` without cutting the release in the same session — remote installs fail until the tag exists.
