# TokenLens

> [中文版](#中文) | [English](#english)

---

<h2 id="english">English</h2>

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

---

<h2 id="中文">中文</h2>

TokenLens 是一款 macOS 菜单栏应用，自动监控本地 AI Coding Agent 的 LLM Token 用量。无需代理、无需 HTTPS 解密、无需网络拦截。它直接读取 agent 生成的本地 session 记录，在菜单栏和设置窗口中展示费用与 Token 统计。

### 核心功能

- **菜单栏显示** — 展示今日/本月/全部的费用或 Token 数
- **实时 Token 动画** — 新用量到达时，菜单栏动态显示 input/output tokens
- **自动扫描** — 启动时自动读取 Codex、Claude Code、pi、OpenCode 的历史 session 记录
- **后台监听** — 基于 FSEvents 实时监听新会话
- **内置定价** — 首次启动自动从 [models.dev](https://models.dev) 初始化模型价格
- **隐私优先** — 不存储 prompt、response、tool output、API key、Authorization 等任何敏感内容

### 支持的 Agent

| Agent | 默认路径 |
|---|---|
| Codex | `~/.codex/sessions/**/*.jsonl` |
| Claude Code | `~/.claude/projects/**/*.jsonl` |
| pi | `~/.pi/agent/sessions/**/*.jsonl` |
| OpenCode | `~/.local/share/opencode/opencode.db` |

所有 source 始终启用，目录或数据库不存在时静默跳过，后续出现后后台自动补扫。

### 安装

#### Homebrew

```bash
brew install --cask tokenlens
```

#### 下载预构建版本

从 [Releases](https://github.com/return764/token-lens/releases) 下载最新的 `.dmg`，打开后将 **TokenLens** 拖入 `/Applications`。

> 首次启动如提示「无法验证开发者」：右键点击 → **打开**即可。

#### 从源码构建

需要 **macOS 14+** 和 **Xcode 15+**（Swift 5.9）。

```bash
git clone https://github.com/return764/token-lens.git
cd token-lens
swift build -c release
./scripts/build-release.sh
open .build/TokenLens.app
```

创建 DMG：

```bash
DMG=1 ./scripts/build-release.sh
```

### 系统要求

- macOS 14+
- 安装了至少一个受支持的 AI Coding Agent

### 隐私

所有数据仅存储在本机。TokenLens **不会**保存或上传：

- Prompt / 消息内容
- Response / 工具调用输出
- API key / Authorization 头

仅匿名的用量摘要（时间戳、模型、Token 数、费用）保存在本地 SQLite 数据库中：`~/Library/Application Support/TokenLens/tokenlens.sqlite`。
