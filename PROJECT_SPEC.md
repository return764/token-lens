# TokenLens 项目规格

> 最后更新：2026-06-15  
> 当前规格：Local Agent Record Scanner MVP  
> 非当前目标：网络捕获 / MITM / Network Extension，详见 `docs/plans/future/network-capture-plan.md`

## 1. 项目目标

TokenLens 是一个 macOS 本地优先的 LLM token 用量监控应用。当前 MVP 不拦截网络，而是自动读取本机 agent 工具的本地 JSONL 使用记录，提取 usage 数据，写入 SQLite，并在菜单栏与 Settings 中展示消耗。

核心目标：

1. 用户启动 App 后自动看到 Codex、Claude Code、pi 的历史与新增 token 消耗。
2. 不需要配置 HTTP_PROXY / HTTPS_PROXY。
3. 不安装 Root CA，不做 HTTPS 解密。
4. 不启用 Network Extension 或 VPN 类能力。
5. 只保存 usage 摘要与必要元数据，不保存 prompt、response、tool output、Authorization、API key。

## 2. 应用形态与技术栈

- **平台**：macOS 14+
- **语言**：Swift 5.9+
- **UI**：SwiftUI + MenuBarExtra + Settings window
- **数据库**：SQLite via GRDB
- **本地数据源**：Codex、Claude Code、pi JSONL session logs
- **模型价格**：首次启动从 `https://models.dev/api.json` 初始化到本地 `models` 表

## 3. 当前数据流

```text
Codex / Claude Code / pi 本地 JSONL
  ↓
LocalUsageAdapter
  ↓
LocalSourcesBackgroundService
  ├─ 启动 catch-up scan
  ├─ FSEvents 监听 root 目录
  └─ 周期 reconcile 兜底
  ↓
LocalJSONLIncrementalReader
  ↓
LocalScanRepository
  ├─ local_usage_imports key 去重
  ├─ token_usages 写入
  └─ local_scan_files checkpoint 更新
  ↓
MenuBar + Settings
```

## 4. MVP 范围

### 必须支持

1. macOS 菜单栏 App。
2. 本地 SQLite 账本。
3. Codex / Claude Code / pi 三个内置 source 始终启用。
4. 启动时 catch-up 扫描历史 JSONL。
5. 后台监听新增 JSONL 内容并增量导入。
6. 只读取新增完整行；半行等待下一次写入；文件截断/轮转可重读。
7. 对重复 watcher 事件、重复扫描、fork/复制文件做 key-based 幂等去重。
8. 支持跨行解析上下文（session/cwd/provider/model），上下文只保存非敏感元数据。
9. token_usages 记录 agentic_tool、provider、model、token 维度、cost、created_at。
10. 从 models.dev 初始化模型价格；无价格时 cost 为 0。
11. 菜单栏显示选定时间范围内 cost 或 tokens；有新增用量时临时显示 live input/output tokens。
12. Settings 显示最近用量、Local Sources 状态、监控显示设置。

### 当前明确不做

- CLI（如 `token-lens scan/watch`）。
- HTTP/HTTPS 本地代理。
- MITM / Root CA / HTTPS 解密。
- Network Extension 透明捕获。
- VPN / 代理冲突检测。
- Prompt/response 保存或回放。
- tokenizer 估算没有 usage 的会话内容。
- daily_usage 预聚合。
- 网络请求错误率/延迟统计。
- 云同步 / 团队账号 / Windows / Linux。

## 5. 数据库 Schema（当前）

### settings

```sql
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

### token_usages

```sql
CREATE TABLE IF NOT EXISTS token_usages (
  id TEXT PRIMARY KEY,
  agentic_tool TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  model TEXT,
  input_tokens INTEGER DEFAULT 0,
  output_tokens INTEGER DEFAULT 0,
  cached_input_tokens INTEGER DEFAULT 0,
  cache_write_tokens INTEGER DEFAULT 0,
  reasoning_tokens INTEGER DEFAULT 0,
  total_tokens INTEGER DEFAULT 0,
  cost_usd REAL DEFAULT 0,
  created_at TEXT NOT NULL
);
```

### local_scan_sources

记录每个内置 source 的扫描/监听状态。

```sql
CREATE TABLE IF NOT EXISTS local_scan_sources (
  source_tool TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  root_path TEXT NOT NULL,
  status TEXT NOT NULL,
  last_scan_started_at TEXT,
  last_scan_finished_at TEXT,
  files_seen INTEGER DEFAULT 0,
  files_scanned INTEGER DEFAULT 0,
  events_imported INTEGER DEFAULT 0,
  parse_error_count INTEGER DEFAULT 0,
  last_error TEXT,
  updated_at TEXT NOT NULL
);
```

### local_scan_files

记录文件级增量读取 checkpoint 与解析上下文。

```sql
CREATE TABLE IF NOT EXISTS local_scan_files (
  id TEXT PRIMARY KEY,
  source_tool TEXT NOT NULL,
  path TEXT NOT NULL,
  file_size INTEGER DEFAULT 0,
  modified_at TEXT,
  file_id TEXT,
  read_offset INTEGER DEFAULT 0,
  parse_context_json TEXT,
  last_scanned_at TEXT,
  imported_event_count INTEGER DEFAULT 0,
  status TEXT NOT NULL,
  last_error TEXT,
  UNIQUE(source_tool, path)
);
```

### local_usage_imports

事件级幂等表。唯一键由 adapter 生成，不能包含 prompt/response/tool output 等敏感内容。

```sql
CREATE TABLE IF NOT EXISTS local_usage_imports (
  key TEXT PRIMARY KEY,
  source_tool TEXT NOT NULL,
  source_file TEXT NOT NULL,
  token_usage_id TEXT NOT NULL,
  imported_at TEXT NOT NULL
);
```

### models

本地模型价格表，由 `ModelsSeeder` 从 models.dev 初始化。

```sql
CREATE TABLE IF NOT EXISTS models (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  model TEXT NOT NULL,
  input_price REAL DEFAULT 0,
  output_price REAL DEFAULT 0,
  cached_input_price REAL DEFAULT 0,
  reasoning_price REAL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'USD',
  effective_from TEXT NOT NULL,
  effective_to TEXT,
  created_at TEXT NOT NULL
);
```

## 6. Adapter 规范

`LocalUsageAdapter` 负责发现文件、解析全文件、解析增量行、恢复/更新解析上下文。

核心要求：

- 只对 usage-bearing 事件生成 `LocalUsageEvent`。
- 无 usage 的消息可用于临时解析上下文，但不得入库。
- `LocalUsageEvent.key` 必须稳定，优先用原生稳定 id；没有稳定 id 时使用 usage 指纹 hash。
- hash 输入只能包含 timestamp/provider/model/token/cost 等非敏感字段。
- `parse_context_json` 只允许保存 session id、cwd、provider、model 等元数据。

当前内置 adapter：

| Source | Adapter | 默认路径 |
|---|---|---|
| Codex | `CodexLocalUsageAdapter` | `~/.codex/sessions/**/*.jsonl` |
| Claude Code | `ClaudeCodeLocalUsageAdapter` | `~/.claude/projects/**/*.jsonl` |
| pi | `PiLocalUsageAdapter` | `~/.pi/agent/sessions/**/*.jsonl` |

## 7. 隐私与安全要求

必须满足：

1. 不保存 prompt/messages。
2. 不保存 response/tool output/thinking 原文。
3. 不保存 Authorization/API key。
4. 去重 key 和 parse context 不包含原始内容。
5. 解析错误信息需要截断/脱敏，不回显原始 JSONL 内容。
6. 数据只存本地 SQLite。
7. App 不上传使用记录；仅在首次/空表时访问 models.dev 获取公开模型价格。

## 8. 当前验收标准

- `swift build` 成功。
- `swift test` 全绿（当前 80 tests）。
- 启动 App 后自动扫描存在的 Codex / Claude Code / pi 目录。
- 目录不存在不报错；后续出现会重试。
- 新增 JSONL usage 后，后台导入并刷新 UI。
- 重复扫描或重复文件事件不会重复计费。
- Settings 能显示 Local Sources 状态和最近 usage。
- MenuBar 能显示 cost/tokens，并在新导入时显示 live tokens。

## 9. 未来可能期望

网络层相关能力不属于当前规格，已从实现计划中抽离：

- HTTP/HTTPS 本地代理
- MITM 精确模式
- Network Extension 透明捕获
- FlowFilter / Provider 域名白名单
- Upstream Proxy / VPN 冲突提示
- 网络请求延迟、错误率、流量统计

详见：`docs/plans/future/network-capture-plan.md`。
