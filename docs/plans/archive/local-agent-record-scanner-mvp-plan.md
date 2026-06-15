# Local Agent Record Scanner MVP 计划

> 状态：**Completed / Archived** — 2026-06-15  
> 最后更新：2026-06-15  
> 当前实现见：`docs/project.md` 与 `docs/implementation-plan.md`

## 1. 产品决策

TokenLens MVP 采用本地记录扫描，而不是网络捕获：

```text
Codex / Claude Code / pi 本地 JSONL
  ↓
LocalUsageAdapter
  ↓
LocalSourcesBackgroundService / LocalUsageScanner
  ↓
SQLite token_usages
  ↓
MenuBar + Settings
```

## 2. 已实现范围

| 能力 | 状态 |
|---|---|
| Codex / Claude Code / pi 三个 source 始终启用 | ✅ |
| 默认扫描路径 | ✅ |
| LocalUsageAdapter 抽象 | ✅ |
| LocalUsageEvent 标准化 | ✅ |
| `token_usages` 写入 | ✅ |
| `local_scan_sources` 状态 | ✅ |
| `local_scan_files` checkpoint | ✅ |
| `local_usage_imports` key 去重 | ✅ |
| CostCalculator + `models` 价格表 | ✅ |
| App 启动自动扫描 | ✅ |
| Settings Local Sources + Rescan Now | ✅ |
| 不保存 prompt/response/tool output/API key | ✅ |

## 3. 当前默认路径

| Source | 默认路径 | 文件类型 |
|---|---|---|
| Codex | `~/.codex/sessions/**/*.jsonl` | JSONL |
| Claude Code | `~/.claude/projects/**/*.jsonl` | JSONL |
| pi | `~/.pi/agent/sessions/**/*.jsonl` | JSONL |

目录不存在不是错误；watcher 会定期重试。

## 4. 当前标准事件

```swift
public struct LocalUsageEvent: Equatable {
    public let key: String
    public let sourceTool: String
    public let sourceFile: String
    public let sourceEventId: String
    public let sourceSessionId: String?
    public let sourceCwd: String?
    public let timestamp: Date
    public let providerId: String?
    public let model: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let costUsd: Double?
}
```

导入时映射到 `token_usages`：

| LocalUsageEvent | token_usages |
|---|---|
| `sourceTool` | `agentic_tool` |
| `providerId` 或 fallback | `provider_id` |
| `model` | `model` |
| `inputTokens` | `input_tokens` |
| `outputTokens` | `output_tokens` |
| `cacheReadTokens` | `cached_input_tokens` |
| `cacheWriteTokens` | `cache_write_tokens` |
| `reasoningTokens` | `reasoning_tokens` |
| `totalTokens` | `total_tokens` |
| `costUsd` 或 CostCalculator | `cost_usd` |
| `timestamp` | `created_at` |

`sourceFile/sourceEventId/sourceSessionId/sourceCwd` 只用于解析、诊断或去重来源，不写入 `token_usages`。

## 5. 当前 Schema 摘要

MVP 当前有 6 张表：

- `settings`
- `token_usages`
- `local_scan_sources`
- `local_scan_files`
- `local_usage_imports`
- `models`

历史计划中的 `model_calls` / `daily_usage` 已被 `token_usages` 瘦身账本取代。

## 6. Source 解析规则（当前）

### pi

- 扫描 `~/.pi/agent/sessions/**/*.jsonl`。
- 解析 assistant message 中的 usage。
- 支持 session/cwd 轻量上下文。
- 使用 native id 或 usage key 去重。

### Codex

- 扫描 `~/.codex/sessions/**/*.jsonl`。
- 优先解析 `event_msg` + `payload.type == token_count`。
- 使用 `last_token_usage`，避免 cumulative total 重复累计。
- 使用 context fallback 填充 model/provider/session/cwd。
- 无稳定 id 时使用 canonical usage fingerprint。

### Claude Code

- 扫描 `~/.claude/projects/**/*.jsonl`。
- 解析 assistant/result/message 事件中的 usage。
- 支持 input/output/cache_creation/cache_read/costUSD。
- 跳过无 usage 的 summary/user message。

## 7. 隐私规则

- 只导入 usage、model、provider、timestamp、source metadata。
- 不导入 prompt、response、tool output、thinking、Authorization、API key。
- `key` hash 输入不包含 path/cwd/raw JSON。
- parse error 不包含原始内容片段。

## 8. 验收状态

已通过当前测试集：

```text
✅ swift test — 80 tests, 0 failures
```

相关测试：

- `PiLocalUsageAdapterTests`
- `CodexLocalUsageAdapterTests`
- `ClaudeCodeLocalUsageAdapterTests`
- `LocalUsageScannerTests`
- `LocalScanRepositoryTests`
- `LocalScanRepositoryIncrementalTests`
- `PrivacyLocalWatcherTests`
- `ForkKeyTests`

## 9. 后续非 MVP

- 支持 Cursor / Cline / Roo / Gemini / Aider。
- 自定义扫描路径。
- 导入错误详情展示。
- 高级 Dashboard。
- 网络捕获能力（见 `docs/plans/future/network-capture-plan.md`）。
