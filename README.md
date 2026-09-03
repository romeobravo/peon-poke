# peon-poke

<div align="center">

![macOS](https://img.shields.io/badge/macOS-blue) ![Force Touch](https://img.shields.io/badge/Force_Touch_trackpad-required-ffab01) ![License](https://img.shields.io/badge/license-MIT-green)

![Claude Code](https://img.shields.io/badge/Claude_Code-hook-ffab01) ![Codex](https://img.shields.io/badge/Codex-adapter-ffab01) ![pi](https://img.shields.io/badge/pi-extension-ffab01) ![oh-my-pi](https://img.shields.io/badge/oh--my--pi-extension-ffab01) ![Gemini CLI](https://img.shields.io/badge/Gemini_CLI-adapter-ffab01) ![Grok Build](https://img.shields.io/badge/Grok_Build-adapter-ffab01) ![Cursor](https://img.shields.io/badge/Cursor-adapter-ffab01)

**Silent trackpad haptics on Mac for when your AI coding agent needs you. Office-friendly sibling of [peon-ping](https://github.com/PeonPing/peon-ping).**

</div>

AI coding agents don't notify you when they finish or need permission. You tab away, lose focus, and waste minutes getting back into flow. `peon-poke` fixes this the quiet way: instead of sound, it **boops your Force Touch trackpad** — no volume, no headphones required, nobody around you hears a thing. Your finger resting on the glass is all it takes.

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

- macOS with a **Force Touch trackpad** (2015+ MacBook, Magic Trackpad 2/3)
- `clang` (build), `python3` (config parsing)
- arm64 notes: the unexported-symbol resolver decodes arm64 `BL` instructions (x86_64 Macs use the classic path)

## Install

```bash
git clone <this repo> && cd peon-poke
bash install.sh
```

The installer:

1. builds `bin/poke` and installs everything to `~/.peon-poke/`
2. writes `~/.config/peon-poke/config.json` (kept on reinstall)
3. registers hooks for every agent it detects: Claude Code, Codex, pi, oh-my-pi

Quick test:

```bash
~/.peon-poke/bin/poke           # chirp, the default boop
~/.peon-poke/bin/poke skrrt     # audition a named pattern
```

## Patterns

`boop` is driven by **gap sequences**: a comma-separated list of millisecond gaps between pulses (one pulse per gap, plus a final pulse):

```bash
~/.peon-poke/bin/poke                 # default: chirp
~/.peon-poke/bin/poke 60,120,40,80     # your own rhythm
~/.peon-poke/bin/poke [60, 120, 40]    # brackets/spaces also fine
```

Built-in named patterns:

| Name | Gaps (ms) | Feel |
|---|---|---|
| `boop` | — | single firm click |
| `chirp` *(default)* | `20,20,20,200,20,20,20,200,20,20,20` | zzt · zzt · zzt, crisp notification |
| `skrrt` | `20,20,20,20,20,20,200,20,20,20,20,20,20` | double rattle, urgent |
| `callme` | `60,120,40,80,40,120,60,300,60,120,60` | syncopated riff, question-answer |
| `rimshot` | `50,80,50,120,150` | galloping ba-dum-tss |
| `heartbeat` | `200,700,200,700,200,700` | gentle heartbeat pairs |
| `slowdown` | `200,162,132,107,87,70,57,46,37,30,25,20` | precomputed exponential ramp, classic decelerando |

Click intensity defaults to 6 (firm); override with `POKE_PATTERN` (valid ids: 1–6, 15, 16 — 1 is a light tick, 15/16 deep thunks).

## Configuration

Everything lives in `~/.config/peon-poke/config.json`:

```json
{
  "enabled": true,
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
    "task.complete": "chirp",
    "task.error": "skrrt",
    "input.required": "callme"
  }
}
```

- `categories` — which events boop at all (taxonomy shared with peon-ping)
- `patterns` — any named pattern or a raw gap list works, e.g. `"task.complete": "60,120,40"`

The pi/oh-my-pi extension also honors `POKE_ARGS` to bypass `poke.sh` and drive `bin/poke` directly (names or gap lists).

## Agent support

| Agent | Mechanism | Setup |
|---|---|---|
| Claude Code | native hooks | automatic (`install.sh`) |
| Codex | `notify` in `~/.codex/config.toml` | automatic |
| pi | extension (`agent_settled`, `ui_prompt_start`) | automatic |
| oh-my-pi | extension | automatic |
| Gemini CLI | lifecycle hooks | manual: point hooks at `~/.peon-poke/adapters/gemini.sh <Event>` |
| Grok Build | `~/.grok/hooks/peon-poke.json` | manual: `"command": "bash ~/.peon-poke/adapters/grok.sh"` |
| Cursor | `~/.cursor/hooks.json` | manual: see header of `adapters/cursor.sh` |

Adapters are thin: read the agent's event (argv or stdin JSON), map to a category, exec `poke.sh <category>`. Porting more of peon-ping's adapters (amp, kimi, qwen, kiro, windsurf, …) follows the same two-dozen-line pattern — PRs welcome.

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

`boop` talks to the trackpad's haptic actuator through the private `MultitouchSupport.framework` — the same route HapticKey uses — which (unlike `NSHapticFeedbackManager`) does **not** require a finger on the glass while firing. On macOS 26 (Tahoe) several long-standing quirks are handled automatically:

- `MTDeviceGetDeviceID` now writes through an out-pointer
- `MTActuatorCreateFromDeviceID`'s `IOPropertyMatch` no longer matches, so the actuator service is found by class (`AppleActuatorDevice`)
- `MTActuatorCreate` is no longer exported from the dyld shared cache — its address is recovered at runtime by decoding the `BL` call inside the exported `MTActuatorCreateFromDeviceID`

## Uninstall

```bash
bash uninstall.sh          # removes hooks + ~/.peon-poke, keeps config
bash uninstall.sh --purge  # also removes config
```

## FAQ

**Can I feel it without touching the trackpad?** No — haptics are vibration; you need a finger resting on the glass to feel it. But no *press* or gesture is required, unlike the public API.

**Does it work on Magic Trackpad 2/3?** Yes, when connected.

**Why did nothing happen?** Run `~/.peon-poke/bin/poke boop` — if the single click doesn't fire, you have no Force Touch hardware. If it fires but hooks don't, check `categories` in config.json.

**Is this safe?** The actuator is driven exactly as macOS itself drives it. The API is private and may break between macOS releases (exit code stays 0 so agents are never disturbed).

## Credits

- [peon-ping](https://github.com/PeonPing/peon-ping) — architecture, event taxonomy, and adapter patterns
- [HapticKey](https://github.com/niw/HapticKey) — the original MultitouchSupport haptic technique

## License

[MIT](LICENSE)
