# peon-poke

<div align="center">

<img src="assets/peon-poke-logo.png" width="200" height="200" alt="peon-poke logo">

![macOS](https://img.shields.io/badge/macOS-blue) ![Force Touch](https://img.shields.io/badge/Force_Touch_trackpad-required-ffab01) ![License](https://img.shields.io/badge/license-MIT-green)

![Claude Code](https://img.shields.io/badge/Claude_Code-hook-ffab01) ![Codex](https://img.shields.io/badge/Codex-adapter-ffab01) ![OpenCode](https://img.shields.io/badge/OpenCode-plugin-ffab01) ![pi](https://img.shields.io/badge/pi-extension-ffab01) ![oh-my-pi](https://img.shields.io/badge/oh--my--pi-extension-ffab01) ![Gemini CLI](https://img.shields.io/badge/Gemini_CLI-adapter-ffab01) ![Grok Build](https://img.shields.io/badge/Grok_Build-adapter-ffab01) ![Cursor](https://img.shields.io/badge/Cursor-adapter-ffab01)

**Your trackpad taps you when your AI coding agent needs you. Quiet sibling of [peon-ping](https://github.com/PeonPing/peon-ping).**

</div>

AI coding agents don't tell you when they finish or need your input. You tab away, and minutes pass before you notice. `peon-poke` fixes this quietly: instead of sound, it taps your Force Touch trackpad. With your hands on the laptop, you feel it right through the palm rest. No volume, no headphones.

It shares its events and config style with [peon-ping](https://github.com/PeonPing/peon-ping), but drives the trackpad's haptic actuator directly. That route works even without a finger on the glass.

---

- [Requirements](#requirements)
- [Install](#install)
- [Patterns](#patterns)
- [Configuration](#configuration)
- [The peon-poke command](#the-peon-poke-command)
- [Agent support](#agent-support)
- [How it works](#how-it-works)
- [Uninstall](#uninstall)
- [FAQ](#faq)
- [Credits](#credits)
- [License](#license)

---

## Requirements

- A MacBook with a built-in Force Touch trackpad (2015 or newer). External Magic Trackpads don't work.
- macOS 12 (Monterey) or newer.
- `python3` 3.8 or newer; the version that ships with macOS is fine.
- Building from source needs `clang`. Homebrew and `git clone` installs build locally; the curl installer ships a precompiled binary.

## Install

### Option 1: Homebrew (recommended)

```bash
brew install romeobravo/tap/peon-poke
peon-poke setup    # registers hooks for detected agents
```

### Option 2: Installer script

```bash
curl -fsSL https://raw.githubusercontent.com/romeobravo/peon-poke/main/install-remote.sh | bash
```

Downloads the precompiled binary and runtime files, checks each one against the release's checksums, and runs setup.

### Option 3: Inspect and install from source

```bash
git clone https://github.com/romeobravo/peon-poke
cd peon-poke
less install.sh src/poke.c   # what you see is what runs
bash install.sh
```

Every install ends in the same setup step. It installs everything to `~/.peon-poke/`, creates `~/.config/peon-poke/config.json` if you don't have one yet, and registers hooks for every agent it detects: Claude Code, Codex, OpenCode, pi, and oh-my-pi.

Quick test:

```bash
~/.peon-poke/bin/poke           # fortune, the default pattern
~/.peon-poke/bin/poke skrrt     # audition a named pattern
```

## Patterns

A pattern is a list of pauses between pulses, in milliseconds:

```bash
~/.peon-poke/bin/poke                 # default: fortune
~/.peon-poke/bin/poke 60,120,40,80     # your own rhythm
~/.peon-poke/bin/poke '[60, 120, 40]'  # brackets and spaces are fine, keep it one argument
```

Each pause is limited to 0–10000 ms, so a typo can't hang the process.

Built-in named patterns:

| Name | Pauses (ms) | Feel |
|---|---|---|
| 👆 `boop` | — | single firm click |
| 🎡 `fortune` *(default)* | `50,80,140,240,400` | fortune wheel: fast ticks slowing to a stop |
| 🐦 `chirp` | `20,20,20,200,20,20,20,200,20,20,20` | zzt · zzt · zzt, crisp notification |
| 💨 `skrrt` | `20,20,20,20,20,20,200,20,20,20,20,20,20` | double rattle, urgent |
| 📞 `callme` | `60,120,40,80,40,120,60,300,60,120,60` | syncopated riff, question-answer |
| 🥁 `rimshot` | `50,80,50,120,150` | galloping ba-dum-tss |
| 💓 `heartbeat` | `200,700,200,700,200,700` | gentle heartbeat pairs |
| 🚀 `rampup` | `200,162,132,107,87,70,57,46,37,30,25,20` | slow start, rapid finish |

Click intensity is set with `strength` in config.json (see below).

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

- `strength` — click intensity for all pokes: 1–6 (1 = light tick, 6 = firm press). Default 6; other values fall back to 6
- `categories` — which events poke at all
- `patterns` — any named pattern or a raw pause list works, e.g. `"task.complete": "60,120,40"`
- `custom` — define your own named patterns or override built-ins: `"custom": {"doorbell": "200,700,200,700"}` makes `doorbell` available anywhere a name is used

Test any pattern without waiting for an agent: `peon-poke play doorbell` (or a raw list: `peon-poke play 60,120,40`).

## The peon-poke command

Everything except the haptic core is one CLI, available as `peon-poke` on your PATH after setup:

```
peon-poke play <pattern>                 # audition a pattern now (default: task-complete pattern)
peon-poke doctor                        # installation + config health report
peon-poke setup / uninstall [--purge]
```

`peon-poke dispatch <category>` is what hooks call; it never blocks or fails the calling agent.

## Agent support

| Agent | Setup |
|---|---|
| Claude Code | automatic |
| Codex | automatic |
| OpenCode | automatic |
| pi | automatic |
| oh-my-pi | automatic |
| Gemini CLI | manual: point hooks at `~/.peon-poke/adapters/gemini.sh <Event>` |
| Grok Build | manual: `"command": "bash ~/.peon-poke/adapters/grok.sh"` in `~/.grok/hooks/peon-poke.json` |
| Cursor | manual: `{ "hooks": [{ "event": "stop", "command": "bash ~/.peon-poke/adapters/cursor.sh stop" }] }` in `~/.cursor/hooks.json` |

Codex allows exactly one `notify` program. If your `~/.codex/config.toml` already has one, setup leaves it alone and skips registration with a warning. To get pokes anyway, point `notify` at a small script of your own that calls both programs; Codex passes the same JSON argument through.

Missing your agent? Porting one is mostly an event table — PRs welcome.

## How it works

```
agent event ──► hook / plugin / adapter ──► peon-poke dispatch <category>
                                              │  config.json: enabled? which pattern?
                                              ▼
                                          bin/poke <pattern args>
                                              │  MultitouchSupport.framework (private)
                                              ▼
                                          trackpad actuator 💥
```

`poke` talks to the trackpad's haptic actuator through the private `MultitouchSupport.framework` — the same route HapticKey uses. Unlike the public API, it fires without a finger on the glass. Changes in newer macOS versions are handled automatically.

## Uninstall

```bash
peon-poke-uninstall          # removes hooks + ~/.peon-poke, keeps config
peon-poke-uninstall --purge  # also removes config
```

No `peon-poke-uninstall` on your PATH? Use `peon-poke uninstall [--purge]` instead.

Uninstall removes only what peon-poke installed: its own hooks and files. Your settings, notes, and anything it doesn't recognize as its own survive untouched.

## FAQ

**Do I need to keep a finger on the trackpad?** No. Haptics are vibration: you feel them with your hands resting on the laptop, in normal typing position. No press or gesture is ever required.

**Does it work on a Magic Trackpad (2/3)?** No. External Magic Trackpads never expose their taptic engine to `poke`; only the built-in Force Touch trackpad works. With the lid closed (clamshell mode) the built-in trackpad is asleep, so `poke` prints a short note on stderr and exits without firing.

**Why did nothing happen?** Run `~/.peon-poke/bin/poke boop`. If the single click doesn't fire, you have no Force Touch hardware. If it fires but hooks don't, check `categories` in config.json.

**Is this safe?** The actuator is driven exactly as macOS itself drives it. The API is private and may break between macOS releases; when it fails, agents are never disturbed.

## Credits

- [peon-ping](https://github.com/PeonPing/peon-ping) — architecture, event taxonomy, and adapter patterns
- [HapticKey](https://github.com/niw/HapticKey) — the original MultitouchSupport haptic technique

## License

[MIT](LICENSE)
