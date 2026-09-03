# peon-poke

<div align="center">

<img src="assets/peon-poke-logo.png" width="200" height="200" alt="peon-poke logo">

![macOS](https://img.shields.io/badge/macOS-blue) ![Force Touch](https://img.shields.io/badge/Force_Touch_trackpad-required-ffab01) ![License](https://img.shields.io/badge/license-MIT-green)

![Claude Code](https://img.shields.io/badge/Claude_Code-hook-ffab01) ![Codex](https://img.shields.io/badge/Codex-adapter-ffab01) ![OpenCode](https://img.shields.io/badge/OpenCode-plugin-ffab01) ![pi](https://img.shields.io/badge/pi-extension-ffab01) ![oh-my-pi](https://img.shields.io/badge/oh--my--pi-extension-ffab01) ![Gemini CLI](https://img.shields.io/badge/Gemini_CLI-adapter-ffab01) ![Grok Build](https://img.shields.io/badge/Grok_Build-adapter-ffab01) ![Cursor](https://img.shields.io/badge/Cursor-adapter-ffab01)

**Trackpad haptic notifications on Mac for when your AI coding agent needs you. Office-friendly sibling of [peon-ping](https://github.com/PeonPing/peon-ping).**

</div>

AI coding agents don't notify you when they finish or need permission. You tab away, lose focus, and waste minutes getting back into flow. `peon-poke` fixes this the quiet way: instead of sound, it **pokes your Force Touch trackpad** — no volume, no headphones required. With your hands on the laptop, you feel it right through the trackpad.

Structurally a haptic sibling of [peon-ping](https://github.com/PeonPing/peon-ping) (same event taxonomy, adapter architecture, and config style) — but instead of playing Warcraft voice lines, it drives the trackpad actuator directly through the private `MultitouchSupport.framework`. Works **without any finger on the trackpad**, unlike the public `NSHapticFeedbackManager` API.

---

- [Requirements](#requirements)
- [Install](#install)
- [Patterns](#patterns)
- [Configuration](#configuration)
- [Agent support](#agent-support)
- [How it works](#how-it-works)
- [Uninstall](#uninstall)
- [FAQ](#faq)
- [Credits](#credits)
- [License](#license)

---

## Requirements

- macOS 12+ (Monterey) with a **Force Touch trackpad** (2015+ MacBook, Magic Trackpad 2/3)
- `python3` (hook registration and adapters)
- `clang` only for source builds (Homebrew and the installer ship a precompiled binary)

### Compatibility matrix

| | arm64 (Apple Silicon) | x86_64 (Intel) |
|---|---|---|
| Precompiled binary (installer, Homebrew bottles n/a — builds from source) | ✅ tested on hardware | ✅ ships in the same universal binary; Force Touch path is the same private API, but not hardware-tested by us |
| Source build (`make`) | ✅ | ✅ cross-compiles cleanly |
| Minimum macOS at load time | 12.0 (`-mmacosx-version-min=12.0` in the Makefile) | 12.0 |

The unexported-symbol resolver decodes arm64 `BL` instructions; x86_64 Macs use the classic symbol path. If the actuator quirks differ on an OS/binary combination you run, file an issue — the valid actuation-ID set is empirical (see the source header).

## Install

### Option 1: Homebrew (recommended)

```bash
brew install romeobravo/tap/peon-poke
peon-poke-setup     # registers hooks for detected agents
```

### Option 2: Installer script (precompiled, universal)

```bash
curl -fsSL https://raw.githubusercontent.com/romeobravo/peon-poke/main/install-remote.sh | bash
```

Downloads the precompiled universal binary (arm64 + x86_64, macOS 12+) plus runtime files, verifies everything against the release's `SHA256SUMS` manifest, and runs setup automatically.

### Option 3: Inspect & install from source

```bash
git clone https://github.com/romeobravo/peon-poke
cd peon-poke
less install.sh src/poke.c   # what you see is what runs
bash install.sh
```

Builds `bin/poke` from source (needs `clang`) and runs setup.

Every path ends in the same setup step:

1. obtains `bin/poke` — Homebrew and the installer use the precompiled universal binary; source installs build with `clang`
2. installs everything to `~/.peon-poke/`
3. writes `~/.config/peon-poke/config.json` (kept on reinstall)
4. registers hooks for every agent it detects: Claude Code, Codex, OpenCode, pi, oh-my-pi

Quick test:

```bash
~/.peon-poke/bin/poke           # fortune, the default pattern
~/.peon-poke/bin/poke skrrt     # audition a named pattern
```

## Patterns

`poke` is driven by **gap sequences**: a comma-separated list of millisecond gaps between pulses (one pulse per gap, plus a final pulse):

```bash
~/.peon-poke/bin/poke                 # default: fortune
~/.peon-poke/bin/poke 60,120,40,80     # your own rhythm
~/.peon-poke/bin/poke [60, 120, 40]    # brackets/spaces also fine
```

Each gap is clamped to 0–10000 ms, so a typo can't hang the process.

Built-in named patterns:

| Name | Gaps (ms) | Feel |
|---|---|---|
| 👆 `boop` | — | single firm click |
| 🎡 `fortune` *(default)* | `50,80,140,240,400` | fortune wheel: fast ticks slowing to a stop |
| 🐦 `chirp` | `20,20,20,200,20,20,20,200,20,20,20` | zzt · zzt · zzt, crisp notification |
| 💨 `skrrt` | `20,20,20,20,20,20,200,20,20,20,20,20,20` | double rattle, urgent |
| 📞 `callme` | `60,120,40,80,40,120,60,300,60,120,60` | syncopated riff, question-answer |
| 🥁 `rimshot` | `50,80,50,120,150` | galloping ba-dum-tss |
| 💓 `heartbeat` | `200,700,200,700,200,700` | gentle heartbeat pairs |
| 🚀 `rampup` | `200,162,132,107,87,70,57,46,37,30,25,20` | precomputed exponential ramp, slow ... rapid |

Click intensity defaults to 6 (firm); override with `POKE_PATTERN` (valid ids: 1–6 — 1 is a light tick, 6 a firm press).

## Configuration

Everything lives in `~/.config/peon-poke/config.json`:

```json
{
  "enabled": true,
  "strength": 6,
  "categories": {
    "session.start": false,
    "task.acknowledge": false,
    "task.complete": true,
    "task.error": true,
    "input.required": true
  },
  "patterns": {
    "session.start": "boop",
    "task.acknowledge": "heartbeat",
    "task.complete": "fortune",
    "task.error": "skrrt",
    "input.required": "callme"
  }
}
```

- `strength` — click intensity for all pokes: **1–6** (1 = light tick, 6 = firm press). Default 6; values outside 1–6 fall back to 6
- `categories` — which events poke at all (taxonomy shared with peon-ping)
- `patterns` — any named pattern or a raw gap list works, e.g. `"task.complete": "60,120,40"`; brackets and spaces are fine too (`"[60, 120, 40]"` — passed to `poke` as a single pattern)
- `custom` — define your own named patterns, or override built-ins: `"custom": {"doorbell": "200,700,200,700", "chirp": "40,40,400"}` makes `doorbell` available anywhere a name is used, and redefines `chirp`. Applies wherever patterns resolve (hooks + `poke.sh`); `bin/poke <name>` from a shell uses the built-ins directly

Test any pattern without waiting for an agent: `bash ~/.peon-poke/poke.sh doorbell` (or a raw list: `bash ~/.peon-poke/poke.sh 60,120,40`)

The pi/oh-my-pi extension also honors `POKE_ARGS` to bypass `poke.sh` and drive `bin/poke` directly (names or gap lists).

## Agent support

| Agent | Mechanism | Setup |
|---|---|---|
| Claude Code | native hooks | automatic (`install.sh`) |
| Codex | `notify` in `~/.codex/config.toml` | automatic |
| OpenCode | plugin in `~/.config/opencode/plugin/` (auto-discovered — no config edits) | automatic |
| pi | extension (`agent_settled`, `ui_prompt_start`) | automatic |
| oh-my-pi | extension | automatic |
| Gemini CLI | lifecycle hooks | manual: point hooks at `~/.peon-poke/adapters/gemini.sh <Event>` |
| Grok Build | `~/.grok/hooks/peon-poke.json` | manual: `"command": "bash ~/.peon-poke/adapters/grok.sh"` |
| Cursor | `~/.cursor/hooks.json` | manual: `{ "hooks": [{ "event": "stop", "command": "bash ~/.peon-poke/adapters/cursor.sh stop" }] }` (Cursor has no notification/permission hook — see `adapters/cursor.sh`) |

Adapters are thin: read the agent's event (argv or stdin JSON), map to a category, exec `poke.sh <category>`. Porting more of peon-ping's adapters (amp, kimi, qwen, kiro, windsurf, …) follows the same two-dozen-line pattern — PRs welcome.

**OpenCode event mapping** (contract verified against opencode 1.18): `session.idle` → task complete, `session.error` → task error, `permission.updated` → input required, `session.created` → session start (off by default). Note: app-bundled opencode builds that sandbox their config directory (e.g. Zentty's) don't read `~/.config/opencode` — use a standard opencode install.

**Codex with an existing `notify`:** Codex allows exactly one `notify` program. If your `~/.codex/config.toml` already has one (e.g. the Codex desktop app registers its computer-use client), setup preserves it, removes any stray peon-poke entries older setups left behind, and skips registration with a warning. To get pokes as well, wrap both programs in a tiny script of your own and point `notify` at it — Codex passes the same JSON argument through to whatever you invoke.

## How it works

```
agent event ──► adapter / hook ──► poke.sh <category>
                                      │  config.json: enabled? which pattern?
                                      ▼
                                  bin/poke <pattern args>
                                      │  MultitouchSupport.framework (private)
                                      ▼
                                  trackpad actuator 💥
```

`poke` talks to the trackpad's haptic actuator through the private `MultitouchSupport.framework` — the same route HapticKey uses — which (unlike `NSHapticFeedbackManager`) does **not** require a finger on the glass while firing. On macOS 26 (Tahoe) several long-standing quirks are handled automatically:

- `MTDeviceGetDeviceID` now writes through an out-pointer
- `MTActuatorCreateFromDeviceID`'s `IOPropertyMatch` no longer matches, so the actuator service is found by class (`AppleActuatorDevice`)
- `MTActuatorCreate` is no longer exported from the dyld shared cache — its address is recovered at runtime by decoding the `BL` call inside the exported `MTActuatorCreateFromDeviceID`

## Uninstall

```bash
peon-poke-uninstall          # removes hooks + ~/.peon-poke, keeps config
peon-poke-uninstall --purge  # also removes config
```

`peon-poke-setup` installs this command (symlinked into a directory already on your `PATH`, e.g. `~/.local/bin` — it never creates `PATH` entries or edits shell profiles). If no suitable directory exists, use the fallback:

```bash
bash ~/.peon-poke/uninstall.sh [--purge]
```

The uninstaller only removes the exact `notify` block it manages in `~/.codex/config.toml` and its own entries in `~/.claude/settings.json` (both backed up first, and re-runs never overwrite your original `*.peon-poke-bak` rollback point) — your own notes and settings survive byte-for-byte. Extension files it doesn't recognize as peon-poke's are left in place. Deletion targets are canonicalized and checked against a refuse-list (`/`, your home, anything not recognizable as a peon-poke install); deliberately custom install locations can be forced with `POKE_UNSAFE_RM=1`.

## FAQ

**Do I need to keep a finger on the trackpad?** No — haptics are vibration, so you feel them with your hands resting on the laptop, in normal typing position. No press or gesture is ever required, unlike the public API.

**Does it work on Magic Trackpad 2/3?** Yes, when connected.

**Why did nothing happen?** Run `~/.peon-poke/bin/poke boop` — if the single click doesn't fire, you have no Force Touch hardware. If it fires but hooks don't, check `categories` in config.json.

**Is this safe?** The actuator is driven exactly as macOS itself drives it. The API is private and may break between macOS releases (exit code stays 0 so agents are never disturbed).

## Credits

- [peon-ping](https://github.com/PeonPing/peon-ping) — architecture, event taxonomy, and adapter patterns
- [HapticKey](https://github.com/niw/HapticKey) — the original MultitouchSupport haptic technique

## License

[MIT](LICENSE)
