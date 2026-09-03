# AGENTS.md — peon-poke

macOS trackpad haptic notifications for AI coding agents. Single-file C core (`src/poke.c`) + bash glue + one pi/oh-my-pi TypeScript extension. Runtime installs to `~/.peon-poke/`, config lives in `~/.config/peon-poke/config.json`.

## Invariants — never break these

- `bin/poke` **always exits 0**, even on failure — hooks must never fail the host agent. Diagnostics go to stderr; `POKE_QUIET=1` silences them.
- Gap values are clamped to 0–10000 ms (`GAP_MAX_MS` in `play_sequence`): `usleep` takes an unsigned count, so an unclamped negative gap parks the process for ~71 minutes.
- `poke.sh` fires detached, quiet, and never blocks the calling agent.
- `peon-poke-setup` never clobbers `~/.claude/settings.json`: on parse failure it skips Claude registration and leaves the file byte-identical; otherwise it writes `settings.json.peon-poke-bak` before modifying. `config.json` is only created if missing, never overwritten.
- `install-remote.sh` verifies every fetched file against `SHA256SUMS` **before executing anything**, and hard-fails if the manifest is missing at the install base.

## Build & smoke test

```
make                 # clang -O2 -Wall — must stay warning-free
./bin/poke boop      # single pulse (fires real haptics)
./bin/poke -5,-5,-5  # must return instantly (gap clamping)
./bin/poke nosuch    # usage on stderr, exit 0
```

## dist binary

`dist/poke-darwin-arm64` is committed to git. Homebrew builds from source, but the curl installer ships this binary — **rebuild and refresh it after every `src/poke.c` change**:

```
make && cp bin/poke dist/poke-darwin-arm64
```

## SHA256SUMS

`install-remote.sh` fetches exactly the files listed in `SHA256SUMS` and verifies each one. Whenever you touch `install.sh`, `peon-poke-setup`, `poke.sh`, `config.json`, `dist/poke-darwin-arm64`, `plugins/pi/*.ts`, or `adapters/*.sh`, regenerate and commit the manifest:

```
scripts/sha256sums.sh
```

## Releases

```
scripts/release.sh <X.Y.Z> ["commit message"]
```

Full flow: preflight checks → rebuild → refresh `dist/` → regenerate `SHA256SUMS` → bump `VERSION` → commit → tag `vX.Y.Z` → push main + tag → `gh release create` → bump the Homebrew tap (`scripts/brew-bump.sh`).

**Ordering matters:** the remote installer resolves the latest GitHub release and hard-requires `SHA256SUMS` at that tag. Never push installer/runtime changes to `main` without cutting the release in the same session — remote installs fail until the tag exists.
