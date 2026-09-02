# peon-boop

<div align="center">

![macOS](https://img.shields.io/badge/macOS-blue) ![Force Touch](https://img.shields.io/badge/Force_Touch_trackpad-required-ffab01) ![License](https://img.shields.io/badge/license-MIT-green)

![Claude Code](https://img.shields.io/badge/Claude_Code-hook-ffab01) ![Codex](https://img.shields.io/badge/Codex-adapter-ffab01) ![pi](https://img.shields.io/badge/pi-extension-ffab01) ![oh-my-pi](https://img.shields.io/badge/oh--my--pi-extension-ffab01) ![Gemini CLI](https://img.shields.io/badge/Gemini_CLI-adapter-ffab01) ![Grok Build](https://img.shields.io/badge/Grok_Build-adapter-ffab01) ![Cursor](https://img.shields.io/badge/Cursor-adapter-ffab01)

**Trackpad haptic patterns when your AI coding agent needs attention.**

</div>

AI coding agents don't notify you when they finish or need permission. You tab away, lose focus, and waste minutes getting back into flow. `peon-boop` fixes this the quiet way: instead of sound, it **boops your Force Touch trackpad** — no volume, no headphones required, nobody around you hears a thing. Your finger resting on the glass is all it takes.

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
git clone <this repo> && cd peon-boop
bash install.sh
```

The installer:

1. builds `bin/boop` and installs everything to `~/.peon-boop/`
2. writes `~/.config/peon-boop/config.json` (kept on reinstall)
3. registers hooks for every agent it detects: Claude Code, Codex, pi, oh-my-pi

Quick test:

```bash
~/.peon-boop/bin/boop rampup     # the default task-complete boop
~/.peon-boop/bin/boop sweep      # audition all patterns
```

## Patterns

`boop` supports single pulses, a pattern sweep, and exponential ramps:

| Command | Effect |
|---|---|
| `boop` | one firm click (pattern 6) |
| `boop 3 5 250` | pattern 3, five pulses, 250 ms apart |
| `boop sweep [gap]` | patterns 1–6 in sequence |
| `boop rampup [p n s e]` | **default `6 12 20 200`** — 12 pulses, gaps grow 20→200 ms exponentially (rapid burst easing out) |
| `boop rampdown [p n s e]` | **default `6 12 200 20`** — mirror (slow start accelerating) |

Valid actuation patterns on current firmware: **1–6, 15, 16** (0 and 7–9 are rejected by the trackpad — `sweep` maps them out). 1 is a light tick, 6 a firm press, 15/16 deep thunks.

Ramp gaps interpolate exponentially (geometric progression), so tempo change *feels* constant — like a heartbeat winding up or down. All four parameters are optional positional overrides.

## Configuration

Everything lives in `~/.config/peon-boop/config.json`:

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
    "session.start": "1 1",
    "task.acknowledge": "2 1",
    "task.complete": "rampup",
    "task.error": "16 2 300",
    "input.required": "3 2 400"
  }
}
```

- `categories` — which events boop at all (taxonomy shared with peon-ping)
- `patterns` — the `boop` arguments fired for each event; any command from the table above works (`"rampup"` → the `6 12 20 200` default)

The pi/oh-my-pi extension also honors `BOOP_ARGS` to bypass `boop.sh` and drive `bin/boop` directly.

## Agent support

| Agent | Mechanism | Setup |
|---|---|---|
| Claude Code | native hooks | automatic (`install.sh`) |
| Codex | `notify` in `~/.codex/config.toml` | automatic |
| pi | extension (`agent_settled`, `ui_prompt_start`) | automatic |
| oh-my-pi | extension | automatic |
| Gemini CLI | lifecycle hooks | manual: point hooks at `~/.peon-boop/adapters/gemini.sh <Event>` |
| Grok Build | `~/.grok/hooks/peon-boop.json` | manual: `"command": "bash ~/.peon-boop/adapters/grok.sh"` |
| Cursor | `~/.cursor/hooks.json` | manual: see header of `adapters/cursor.sh` |

Adapters are thin: read the agent's event (argv or stdin JSON), map to a category, exec `boop.sh <category>`. Porting more of peon-ping's adapters (amp, kimi, qwen, kiro, windsurf, …) follows the same two-dozen-line pattern — PRs welcome.

## How it works

```
agent event ──► adapter / hook ──► boop.sh <category>
                                      │  config.json: enabled? which pattern?
                                      ▼
                                  bin/boop <pattern args>
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
bash uninstall.sh          # removes hooks + ~/.peon-boop, keeps config
bash uninstall.sh --purge  # also removes config
```

## FAQ

**Can I feel it without touching the trackpad?** No — haptics are vibration; you need a finger resting on the glass to feel it. But no *press* or gesture is required, unlike the public API.

**Does it work on Magic Trackpad 2/3?** Yes, when connected.

**Why did nothing happen?** Run `~/.peon-boop/bin/boop sweep` — if no pattern fires, you have no Force Touch hardware. If patterns fire but hooks don't, check `categories` in config.json.

**Is this safe?** The actuator is driven exactly as macOS itself drives it. The API is private and may break between macOS releases (exit code stays 0 so agents are never disturbed).

## Credits

- [peon-ping](https://github.com/PeonPing/peon-ping) — architecture, event taxonomy, and adapter patterns
- [HapticKey](https://github.com/niw/HapticKey) — the original MultitouchSupport haptic technique

## License

[MIT](LICENSE)
