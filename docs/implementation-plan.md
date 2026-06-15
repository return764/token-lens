# TokenLens — 实现计划

> 最后更新：2026-06-15 | 当前阶段：Local Agent Record Scanner MVP 已实现

## 当前完成状态总览

| 模块 | 内容 | 状态 |
|---|---|---|
| App/UI | MenuBarExtra、Settings window、最近 usage、Local Sources、菜单栏 cost/tokens/live tokens | ✅ |
| 本地扫描 | Codex / Claude Code / pi adapters | ✅ |
| 后台监听 | 启动 catch-up、FSEvents watcher、周期 reconcile、Rescan Now | ✅ |
| 增量导入 | byte offset、半行保护、truncate 重读、parse context 持久化 | ✅ |
| 幂等去重 | `local_usage_imports.key`，文件/session/fork 无关去重 | ✅ |
| 数据模型 | `token_usages` 瘦身账本；删除 `model_calls` / `daily_usage` 当前依赖 | ✅ |
| 定价 | `models` 表 + models.dev 首次初始化 + CostCalculator | ✅ |
| 隐私 | 不保存 prompt/response/tool output/API key；key/context 脱敏 | ✅ |
| 测试 | 80 tests, 0 failures | ✅ |
| 网络捕获 | 不属于当前实现，已抽离到未来计划 | ⏭️ |

网络相关未实现能力已单独成文：[`docs/plans/future/network-capture-plan.md`](plans/future/network-capture-plan.md)。本文件只描述当前已实现 MVP 与近期计划。

---

## MVP 功能清单

### 应用层

| 功能 | 状态 | 文件 |
|---|---|---|
| macOS 菜单栏 App | ✅ | `Sources/TokenLensApp/App/TokenLensApp.swift` |
| 共享状态与启动任务 | ✅ | `Sources/TokenLensApp/App/AppState.swift` |
| 菜单栏展示 cost/tokens | ✅ | `MenuBar/MenuBarView.swift` |
| 新导入 usage 时展示 live input/output tokens | ✅ | `AppState.swift`, `LocalSourcesBackgroundService.swift` |
| Settings：Recent Usage / Local Sources / Monitoring | ✅ | `Settings/SettingsTab.swift` |
| Rescan Now | ✅ | `AppState.scanLocalRecordsNow()` |

### 数据层

| 功能 | 状态 | 文件 |
|---|---|---|
| SQLite/GRDB 初始化 | ✅ | `Database/DatabaseManager.swift` |
| `settings` | ✅ | `SettingsRepository.swift` |
| `token_usages` CRUD | ✅ | `TokenUsagesRepository.swift` |
| `local_scan_sources` 状态 | ✅ | `LocalScanRepository.swift` |
| `local_scan_files` checkpoint | ✅ | `LocalScanRepository.swift` |
| `local_usage_imports` key 去重 | ✅ | `LocalScanRepository.swift` |
| `models` 价格表 | ✅ | `ModelsRepository.swift` |
| POC reset/rebuild helper | ✅ | `DatabaseManager.resetAndRebuild(at:)` |

### 定价

| 功能 | 状态 | 文件 |
|---|---|---|
| CostCalculator | ✅ | `Core/CostCalculator.swift` |
| models.dev API models | ✅ | `Models/ModelsDevAPIModels.swift` |
| models.dev 拉取服务 | ✅ | `Services/ModelsDevAPIService.swift` |
| 首次/空表 seed | ✅ | `Services/ModelsSeeder.swift` |
| 拉取失败策略：清空 models + `last_synced_at=failed` | ✅ | `ModelsSeeder.swift` |

### 本地扫描与后台监听

| 功能 | 状态 | 文件 |
|---|---|---|
| `LocalUsageAdapter` context-aware 接口 | ✅ | `Core/LocalRecords/LocalUsageModels.swift` |
| Codex adapter | ✅ | `CodexLocalUsageAdapter.swift` |
| Claude Code adapter | ✅ | `ClaudeCodeLocalUsageAdapter.swift` |
| pi adapter | ✅ | `PiLocalUsageAdapter.swift` |
| key 生成 | ✅ | `LocalUsageKeyBuilder.swift` |
| 增量 JSONL reader | ✅ | `LocalJSONLIncrementalReader.swift` |
| 启动 catch-up scanner | ✅ | `LocalUsageScanner.swift` |
| 后台服务 | ✅ | `LocalSourcesBackgroundService.swift` |
| 导入队列/防抖/串行化 | ✅ | `LocalSourceImportQueue.swift` |
| FSEvents watcher | ✅ | `FileSystemEventWatcher.swift` |

---

## 当前数据库表

| 表 | 说明 |
|---|---|
| `settings` | App 配置：菜单栏显示、时间范围、live token 布局等 |
| `token_usages` | token usage 账本 |
| `local_scan_sources` | source 级状态 |
| `local_scan_files` | 文件 checkpoint：`read_offset`、`parse_context_json` 等 |
| `local_usage_imports` | usage 事件去重表 |
| `models` | 模型价格表 |

历史表/概念：

- `model_calls`：已由 `token_usages` 取代。
- `daily_usage`：当前不再维护预聚合。
- `pricing_rules`：当前表名为 `models`，由 `ModelsRepository` 管理。
- `network_requests`：当前 schema 不包含；未来网络捕获再评估。

---

## 当前测试状态

```text
✅ 80 tests, 0 failures
```

重点覆盖：

- DB schema 与 repository。
- token usage 插入/查询。
- models.dev seeding 与 CostCalculator。
- Codex / Claude Code / pi 全量与增量解析。
- JSONL offset reader、半行、truncate。
- checkpoint 与 parse context 持久化。
- key-based 去重与 fork/session/file-independent dedupe。
- FSEvents path expansion/dedupe。
- 隐私约束。
- AppState 菜单栏显示与 Local Sources 刷新。

---

## 近期计划（Local-first）

1. 支持更多本地 source：Cursor / Cline / Roo / Gemini / Aider。
2. 自定义扫描路径或额外 source root。
3. Settings 展示导入错误详情与文件级诊断。
4. models.dev 价格手动刷新与同步状态 UI。
5. 更细的 source/model/provider 汇总视图（仍基于 `token_usages` 即时查询）。
6. 打包分发：Developer ID 签名、notarized DMG、首次启动指引。

## 中长期可能期望

- 高级 Dashboard（趋势图、模型对比、导出）。
- 网络捕获层（HTTP/HTTPS Proxy、MITM、Network Extension），详见 `docs/plans/future/network-capture-plan.md`。
- 云同步 / 团队统计（非当前本地优先 MVP）。
