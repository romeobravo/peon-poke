# peon-poke

<div align="center">

<img src="assets/peon-poke-logo.png" width="200" height="200" alt="peon-poke logo">

![macOS](https://img.shields.io/badge/macOS-blue) ![Force Touch](https://img.shields.io/badge/Force_Touch_trackpad-required-ffab01) ![License](https://img.shields.io/badge/license-MIT-green)

![Claude Code](https://img.shields.io/badge/Claude_Code-hook-ffab01) ![Codex](https://img.shields.io/badge/Codex-adapter-ffab01) ![OpenCode](https://img.shields.io/badge/OpenCode-plugin-ffab01) ![Pi](https://img.shields.io/badge/Pi-extension-ffab01) ![oh-my-pi](https://img.shields.io/badge/oh--my--pi-extension-ffab01) ![Gemini CLI](https://img.shields.io/badge/Gemini_CLI-adapter-ffab01) ![Grok Build](https://img.shields.io/badge/Grok_Build-adapter-ffab01) ![Cursor](https://img.shields.io/badge/Cursor-adapter-ffab01)

**Your trackpad taps you when your AI coding agent needs you. Quiet sibling of [peon-ping](https://github.com/PeonPing/peon-ping).**

</div>

AI coding agents don't tell you when they finish or need your input. You tab away, and minutes pass before you notice. `peon-poke` fixes this quietly: instead of sound, it taps your Force Touch trackpad. With your hands on the laptop, you feel it right through the palm rest. No volume, no headphones.

---

- [Requirements](#requirements)
- [Install](#install)
- [Poke Patterns](#poke-patterns)
- [Agents](#agents)
- [Configuration](#configuration)
- [peon-poke CLI](#peon-poke-cli)
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
less peon-poke src/poke.c   # what you see is what runs
make                        # builds bin/poke (needs clang)
./peon-poke setup           # installs to ~/.peon-poke, registers hooks
```

No `peon-poke` command afterwards? Add it: `ln -s ~/.peon-poke/bin/peon-poke ~/.local/bin/` (or any directory on your PATH).

Every install ends in the same setup step. It installs everything to `~/.peon-poke/`, creates `~/.config/peon-poke/config.json` if you don't have one yet, and registers hooks for every agent it detects: Claude Code, Codex, OpenCode, Pi, and oh-my-pi.

Quick test:

```bash
peon-poke play            # fortune, the default pattern
peon-poke play skrrt     # audition a named pattern
```

## Poke Patterns

A pattern is a list of pauses between pulses, in milliseconds:

```bash
peon-poke play                    # default: fortune
peon-poke play 60,120,40,80     # your own rhythm
peon-poke play '[60, 120, 40]'  # brackets and spaces are fine, keep it one argument
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

## Agents

| Agent | Setup |
|---|---|
| Claude Code | `peon-poke setup claude` |
| Codex | `peon-poke setup codex` |
| OpenCode | `peon-poke setup opencode` |
| Pi | `peon-poke setup pi` |
| oh-my-pi | `peon-poke setup oh-my-pi` |
| Gemini CLI | manual: point hooks at `~/.peon-poke/adapters/gemini.sh <Event>` |
| Grok Build | manual: `"command": "bash ~/.peon-poke/adapters/grok.sh"` in `~/.grok/hooks/peon-poke.json` |
| Cursor | manual: `{ "hooks": [{ "event": "stop", "command": "bash ~/.peon-poke/adapters/cursor.sh stop" }] }` in `~/.cursor/hooks.json` |

Bare `peon-poke setup` registers every agent it detects. The per-agent commands also work when the agent was skipped — e.g. run `peon-poke setup claude` after installing Claude Code. For the manual agents, `peon-poke setup gemini` / `grok` / `cursor` prints the wiring for you.

Codex allows exactly one `notify` program. If your `~/.codex/config.toml` already has one, setup leaves it alone and skips registration with a warning. To get pokes anyway, point `notify` at a small script of your own that calls both programs; Codex passes the same JSON argument through.

Missing your agent? Porting one is mostly an event table — PRs welcome.

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

## peon-poke CLI

Everything except the haptic core is one CLI, available as `peon-poke` on your PATH after setup:

```
peon-poke play <pattern>    # audition a pattern now (default: task-complete pattern)
peon-poke setup [agent]    # install runtime; register one integration or all
peon-poke uninstall [agent] # remove one integration, or everything
peon-poke doctor           # installation + config health report
```

`peon-poke dispatch <category>` is what hooks call; it never blocks or fails the calling agent.

## Uninstall

```bash
peon-poke uninstall          # removes hooks + ~/.peon-poke, keeps config
peon-poke uninstall --purge  # also removes config
peon-poke uninstall pi       # removes one integration, keeps the rest
```

Uninstall removes only what peon-poke installed: its own hooks and files. Your settings, notes, and anything it doesn't recognize as its own survive untouched.

## FAQ

**Do I need to keep a finger on the trackpad?** No. Haptics are vibration: you feel them with your hands resting on the laptop, in normal typing position. No press or gesture is ever required.

**Does it work on a Magic Trackpad (2/3)?** No. External Magic Trackpads never expose their taptic engine to `peon-poke`; only the built-in Force Touch trackpad works. With the lid closed (clamshell mode) the built-in trackpad is asleep, so `peon-poke` prints a short note on stderr and exits without firing.

**Why did nothing happen?** Run `peon-poke play`. If silent, run `peon-poke play boop` — if that doesn't fire either, you have no Force Touch hardware (or `enabled: false` in config.json). If it fires but hooks don't, check `categories` in config.json.

**Is this safe?** The actuator is driven exactly as macOS itself drives it. The API is private and may break between macOS releases; when it fails, agents are never disturbed.

## Credits

- [peon-ping](https://github.com/PeonPing/peon-ping) — architecture, event taxonomy, and adapter patterns
- [HapticKey](https://github.com/niw/HapticKey) — the original MultitouchSupport haptic technique

## License

[MIT](LICENSE)
