# TokenLens — 项目文档

> 最后更新：2026-06-15 | 当前阶段：MVP — Local Agent Record Scanner + Background Watcher

## 1. 项目概述

TokenLens 是一个 macOS 本地优先的 LLM token 用量监控应用。当前实现自动读取 Codex、Claude Code、pi、OpenCode 的本地 session 记录，提取 token usage，写入 SQLite（`token_usages` 表），并在菜单栏和 Settings 展示消耗。

当前 MVP 不需要代理配置，不启用 MITM/CA，不使用 Network Extension。

- **应用形态**：macOS 菜单栏 App + Settings 控制面板
- **技术栈**：SwiftUI + GRDB/SQLite + SPM
- **平台**：macOS 14+
- **语言**：Swift 5.9+

## 2. 当前数据流

```text
Codex / Claude Code / pi / OpenCode 本地 session 记录 (~/.codex, ~/.claude, ~/.pi, ~/.local/share/opencode)
  ↓
LocalUsageAdapter（per-source session change reader）
  ↓
LocalSourcesBackgroundService
  ├─ 启动 catch-up 扫描
  ├─ FSEvents 后台监听
  └─ 周期 reconcile 兜底
  ↓
Adapter session reader（JSONL 增量行或 OpenCode SQLite session delta）
  ↓
LocalScanRepository（key 去重 + checkpoint 事务更新）
  ↓
SQLite token_usages
  ↓
MenuBar + Settings
```

## 3. 当前功能边界

### 已实现

| 功能 | 状态 |
|---|---|
| macOS MenuBarExtra App | ✅ |
| Settings window | ✅ |
| Codex / Claude Code / pi / OpenCode 本地记录扫描 | ✅ |
| FSEvents 后台监听 + 周期 reconcile | ✅ |
| 增量 JSONL reader（offset、半行保护、truncate 重读） | ✅ |
| Context-aware parser（parse_context_json） | ✅ |
| key-based 去重（local_usage_imports） | ✅ |
| token_usages 本地账本 | ✅ |
| models.dev 首次价格初始化 | ✅ |
| CostCalculator | ✅ |
| 菜单栏 cost/tokens + live input/output tokens | ✅ |
| 隐私测试：不保存 prompt/response/tool output/API key | ✅ |

### 当前明确不做

- CLI。
- HTTP/HTTPS 代理。
- MITM / Root CA / HTTPS 解密。
- Network Extension 透明捕获。
- Upstream Proxy。
- VPN/代理冲突检测。
- Codex / Claude Code / pi / OpenCode 单独关闭开关。
- Cursor / Cline / Roo / Gemini / Aider 等更多 source。
- tokenizer 估算没有 usage 的文本。
- daily_usage 预聚合。
- 网络请求延迟/错误率统计。

网络捕获相关设想见：[`docs/plans/future/network-capture-plan.md`](plans/future/network-capture-plan.md)。

## 4. 数据库 Schema（6 张表）

| 表名 | 用途 |
|---|---|
| `settings` | key/value 配置 |
| `token_usages` | token 消耗账本（agentic_tool/provider/model/tokens/cost） |
| `local_scan_sources` | source 级扫描/监听状态 |
| `local_scan_files` | session record 级 checkpoint（read_offset + parse_context_json） |
| `local_usage_imports` | 事件级幂等去重账本 |
| `models` | 模型价格表（来自 models.dev） |

> 历史上的 `model_calls`、`daily_usage`、`pricing_rules` 已被当前 schema 取代：当前用 `token_usages` 和 `models`。

## 5. 默认扫描路径

| Source | 路径 |
|---|---|
| Codex | `~/.codex/sessions/**/*.jsonl` |
| Claude Code | `~/.claude/projects/**/*.jsonl` |
| pi | `~/.pi/agent/sessions/**/*.jsonl` |
| OpenCode | `~/.local/share/opencode/opencode.db` |

所有 source 始终启用。目录或数据库不存在时跳过，watcher 会周期重试。

## 6. 项目结构

```text
TokenLens/
├── Package.swift
├── README.md
├── PROJECT_SPEC.md
├── docs/
│   ├── project.md
│   ├── implementation-plan.md
│   ├── adding-new-local-source.md
│   └── plans/
│       ├── current/
│       ├── future/
│       └── archive/
├── Sources/TokenLensApp/
│   ├── App/
│   │   ├── TokenLensApp.swift
│   │   └── AppState.swift
│   ├── MenuBar/MenuBarView.swift
│   ├── Settings/
│   │   ├── SettingsTab.swift
│   │   └── SettingsView.swift
│   ├── Components/UsageUIComponents.swift
│   ├── Core/
│   │   ├── CostCalculator.swift
│   │   └── LocalRecords/
│   │       ├── LocalUsageModels.swift
│   │       ├── LocalUsageScanner.swift
│   │       ├── LocalSourcesBackgroundService.swift
│   │       ├── LocalSourceImportQueue.swift
│   │       ├── LocalJSONLIncrementalReader.swift
│   │       ├── FileSystemEventWatcher.swift
│   │       ├── LocalUsageKeyBuilder.swift
│   │       ├── CodexLocalUsageAdapter.swift
│   │       ├── ClaudeCodeLocalUsageAdapter.swift
│   │       ├── PiLocalUsageAdapter.swift
│   │       └── OpenCodeLocalUsageAdapter.swift
│   ├── Database/
│   │   ├── DatabaseManager.swift
│   │   ├── TokenUsagesRepository.swift
│   │   ├── LocalScanRepository.swift
│   │   ├── ModelsRepository.swift
│   │   └── SettingsRepository.swift
│   ├── Models/
│   │   ├── DomainModels.swift
│   │   ├── PricingRule.swift
│   │   └── ModelsDevAPIModels.swift
│   ├── Services/
│   │   ├── ModelsDevAPIService.swift
│   │   └── ModelsSeeder.swift
│   └── Shared/ISO8601DateCoding.swift
└── Tests/TokenLensTests/
```

## 7. 测试统计

```text
✅ 102 tests — 0 failures
```

| 测试类 | 测试数 | 覆盖内容 |
|---|---:|---|
| `DatabaseManagerTests` | 5 | schema、默认 settings、增量列、幂等表 |
| `TokenUsagesRepositoryTests` | 3 | insert/fetchRecent/模型字段 |
| `SettingsRepositoryTests` | 4 | 默认值、读写、时间戳 |
| `AppStateTests` | 9 | refresh、菜单栏显示、设置持久化、overview/heatmap |
| `AppStateLocalSourcesTests` | 1 | Local Sources 状态刷新 |
| `LocalScanRepositoryTests` | 8 | key 去重、provider fallback、cost、checkpoint |
| `LocalScanRepositoryIncrementalTests` | 4 | offset 持久化、事务回滚、状态转换 |
| `LocalUsageScannerTests` | 6 | 默认 adapters、catch-up、not_found、parse_error 隔离、统一 session read 路径 |
| `LocalJSONLIncrementalReaderTests` | 9 | offset、半行、空文件、truncate |
| `FileSystemEventWatcherTests` | 3 | JSONL path dedupe / directory expansion、adapter candidate routing |
| `ForkKeyTests` | 3 | 文件/session 无关去重 |
| `ModelsRepositoryBatchTests` | 3 | replaceAll/deleteAll |
| `ModelsSeederTests` | 6 | models.dev seeding、失败策略、跳过无 cost |
| `CostCalculatorTests` | 4 | cost 计算、有效期、无价格 |
| `PiLocalUsageAdapterTests` | 2 | pi 全量/增量解析 |
| `ClaudeCodeLocalUsageAdapterTests` | 2 | Claude Code 全量/增量解析 |
| `CodexLocalUsageAdapterTests` | 4 | Codex token_count、context、bootstrap |
| `OpenCodeLocalUsageAdapterTests` | 7 | OpenCode SQLite aggregate delta、schema error、privacy |
| `DailyUsageHeatmapDataTests` | 4 | heatmap grid、level fallback、zero days |
| `DashboardPageTests` | 3 | dashboard tabs、heatmap ownership |
| `OverviewChartDataTests` | 3 | chart segment/nearest bucket |
| `PrivacyLocalWatcherTests` | 4 | 不保存原文、非 usage 不入库、key 脱敏 |

## 8. 构建与运行

```bash
swift build
swift run
swift test
```

## 9. 隐私保护

| 原则 | 当前实现 |
|---|---|
| 不保存 prompt | `token_usages` 无 prompt/messages 字段；非 usage 行不入库 |
| 不保存 response/tool output | adapter 只产出 usage 事件；隐私测试覆盖 |
| 不保存 Authorization/API key | schema 与 parser 均无相关字段 |
| key 不含敏感内容 | `LocalUsageKeyBuilder` 只使用 usage 指纹字段 |
| parse context 只存元数据 | session/cwd/provider/model 等，用于增量解析 |
| 数据只存本机 | usage 写入本地 SQLite；不上传记录 |
| 唯一网络访问 | `models.dev/api.json` 仅用于公开模型价格初始化 |

## 10. 关键设计决策

| 决策 | 理由 |
|---|---|
| 从网络捕获转向本地记录扫描 MVP | 降低权限/证书/NE 调试风险，先做稳定可用的本地账本 |
| `token_usages` 替代 `model_calls` | 当前目标是 token 消耗，不记录网络请求语义 |
| 不做 `daily_usage` 预聚合 | UI 当前直接读取/汇总 `token_usages` 即可 |
| `models` 替代旧定价 seed | 从 models.dev 获取更完整价格数据 |
| key-based 幂等表 | offset 只说明文件读到哪里，key 才能防重复事件/文件复制 |
| parse context 持久化 | 增量读取仍能补齐 model/provider/session/cwd |
| 统一 session source 接口 | JSONL 文件和 OpenCode SQLite 都表示会变化的本地 session 记录，scanner/import queue 只依赖 adapter 输出的 usage events 与 checkpoint |
| FSEvents + reconcile | FSEvents 只是 hint，周期扫描兜底避免漏事件 |

## 11. 相关文档

- 当前实现计划：[`docs/implementation-plan.md`](implementation-plan.md)
- 新增本地 source：[`docs/adding-new-local-source.md`](adding-new-local-source.md)
- 未来网络捕获：[`docs/plans/future/network-capture-plan.md`](plans/future/network-capture-plan.md)
- 当前规格：[`PROJECT_SPEC.md`](../PROJECT_SPEC.md)
