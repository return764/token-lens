# TokenLens

> English | [中文版](README.zh-CN.md)

TokenLens is a macOS menu bar app that monitors your LLM token consumption — automatically and locally. No proxy, no MITM, no network interception. It reads local session records produced by AI coding agents and shows you cost and token stats at a glance.

### Features

- **Menu bar display** — cost or tokens for today / month / all time
- **Live token feed** — animated input/output token counts when new usage arrives
- **Auto-scanning** — reads Codex, Claude Code, pi, and OpenCode session records on startup
- **Background watcher** — FSEvents-based monitoring for new sessions in real time
- **Built-in pricing** — model prices seeded from [models.dev](https://models.dev) on first launch
- **Privacy-first** — never stores prompts, responses, tool outputs, API keys, or authorization headers

### Supported Agents

| Agent | Default Path |
|---|---|
| Codex | `~/.codex/sessions/**/*.jsonl` |
| Claude Code | `~/.claude/projects/**/*.jsonl` |
| pi | `~/.pi/agent/sessions/**/*.jsonl` |
| OpenCode | `~/.local/share/opencode/opencode.db` |

All sources are always enabled. Missing directories or databases are retried when the watcher detects them later.

### Install

#### Homebrew

```bash
brew install --cask tokenlens
```

#### Download Prebuilt

Download the latest `.dmg` from [Releases](https://github.com/return764/token-lens/releases), open it, and drag **TokenLens** into `/Applications`.

> First launch: right-click → **Open** if the app is unsigned.

#### Build from Source

Requires **macOS 14+** and **Xcode 15+** (Swift 5.9).

```bash
git clone https://github.com/return764/token-lens.git
cd token-lens
swift build -c release
./scripts/build-release.sh
open .build/TokenLens.app
```

To create a DMG:

```bash
DMG=1 ./scripts/build-release.sh
```

### Requirements

- macOS 14+
- One or more of the supported AI coding agents installed locally

### Privacy

All data stays on your machine. TokenLens does **not** save, transmit, or log:

- Prompts / messages
- Responses / tool outputs
- API keys / Authorization headers

Only anonymous usage summaries (timestamps, model, token counts, cost) are stored in a local SQLite database at `~/Library/Application Support/TokenLens/tokenlens.sqlite`.
