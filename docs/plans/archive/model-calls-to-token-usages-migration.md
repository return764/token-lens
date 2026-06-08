# model_calls → token_usages 迁移计划

> 状态：**Completed / Archived** — 2026-06-11 | 归档于 2026-06-11  
> 历史文档：记录当时迁移方案，不代表 2026-06-13 当前实现。当前实现已进一步演进为 `read_offset + parse_context_json + local_usage_imports.key`，价格表也从 `pricing_rules` 演进为 `models`。  
> 当前实现请见：`docs/project.md` 与 `docs/implementation-plan.md`。

## 决策摘要

将 `model_calls` 表重构为 `token_usages`，大幅瘦身 schema，专注于 token 消耗核心功能。砍掉 daily_usage 预聚合和所有聚合 UI，pricing_rules 保留但不暴露 UI。

---

## 1. 新 Schema

### 1.1 token_usages（替代 model_calls）

```sql
CREATE TABLE token_usages (
  id              TEXT PRIMARY KEY,
  agentic_tool    TEXT NOT NULL,        -- 外键 → local_scan_sources.source_tool
  provider_id     TEXT NOT NULL,
  model           TEXT,
  input_tokens    INTEGER DEFAULT 0,
  output_tokens   INTEGER DEFAULT 0,
  cached_input_tokens  INTEGER DEFAULT 0,
  cache_write_tokens   INTEGER DEFAULT 0,
  reasoning_tokens     INTEGER DEFAULT 0,
  total_tokens    INTEGER DEFAULT 0,
  cost_usd        REAL DEFAULT 0,
  created_at      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_token_usages_agentic_tool
ON token_usages(agentic_tool, created_at);

CREATE INDEX IF NOT EXISTS idx_token_usages_created_at
ON token_usages(created_at);

CREATE INDEX IF NOT EXISTS idx_token_usages_provider_model
ON token_usages(provider_id, model);
```

### 1.2 local_scan_files 加行号指针

```sql
-- 在现有 local_scan_files 表上新增列：
ALTER TABLE local_scan_files ADD COLUMN last_scanned_line INTEGER DEFAULT 0;
ALTER TABLE local_scan_files ADD COLUMN total_lines INTEGER DEFAULT 0;
```

去重策略改为：每次扫描从 `last_scanned_line` 行开始，跳过已处理行。不再依赖 `(source_tool, source_file, source_event_id)` 唯一索引。

### 1.3 删除的表

- `daily_usage` — 整表删除
- 唯一索引 `idx_model_calls_local_source_unique` — 随 model_calls 一起删除

### 1.4 保留不改的表

| 表 | 变更 |
|---|------|
| `settings` | 不变 |
| `providers` | 不变 |
| `pricing_rules` | 不变（Repo 保留，UI 删除） |
| `local_scan_sources` | 不变 |
| `local_scan_files` | 加 `last_scanned_line` + `total_lines` |
| `network_requests` | 不变（未来网络功能预留） |

---

## 2. 字段映射：ModelCall → TokenUsage

| ModelCall | TokenUsage | 备注 |
|-----------|------------|------|
| `id` | `id` | 保留 |
| — | `agentic_tool` | 新字段，值来自 source_tool |
| `providerId` | `provider_id` | 保留 |
| `model` | `model` | 保留 |
| `inputTokens` | `input_tokens` | 保留 |
| `outputTokens` | `output_tokens` | 保留 |
| `cachedInputTokens` | `cached_input_tokens` | 保留 |
| `cacheWriteTokens`（缺失） | `cache_write_tokens` | 新增到 Model |
| `reasoningTokens` | `reasoning_tokens` | 保留 |
| `totalTokens` | `total_tokens` | 保留 |
| `costUsd` | `cost_usd` | 保留 |
| `createdAt` | `created_at` | 保留 |
| `networkRequestId` | ❌ 删除 | — |
| `operation` | ❌ 删除 | — |
| `latencyMs` | ❌ 删除 | — |
| `status` | ❌ 删除 | — |
| `errorCode` | ❌ 删除 | — |
| `requestId` | ❌ 删除 | — |
| `streaming` | ❌ 删除 | — |
| `source` | ❌ 删除 | — |
| `sourceTool` | → `agentic_tool` | 改名 |
| `sourceFile` | ❌ 删除 | 去重改用行号 |
| `sourceEventId` | ❌ 删除 | 去重改用行号 |
| `sourceSessionId` | ❌ 删除 | — |
| `sourceCwd` | ❌ 删除 | — |
| `importedAt` | ❌ 删除 | — |

---

## 3. 代码变更清单

### 3.1 Models

| 文件 | 变更 |
|------|------|
| `Models/DomainModels.swift` | `ModelCall` → `TokenUsage`，字段瘦身；删 `DailyUsage` |
| `Models/DomainModels.swift` | 删所有聚合 Stats 类型（`TodayStats`、`ModelStat`、`ProviderStat`、`ProviderModelStat`、`SourceToolStat`、`TopProviderStat`、`TopModelStat`） |

新的 `TokenUsage`：

```swift
public struct TokenUsage: Identifiable {
    public let id: String
    public let agenticTool: String
    public let providerId: String
    public let model: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let costUsd: Double
    public let createdAt: Date
}
```

### 3.2 Database

| 文件 | 变更 |
|------|------|
| `Database/DatabaseManager.swift` | v1_initial_schema：model_calls → token_usages，删 daily_usage，删相关索引；local_scan_files 加行号列 |
| `Database/ModelCallsRepository.swift` | 改名 `TokenUsagesRepository.swift`；只保留 insert + fetchRecent；删所有聚合方法 |
| `Database/DailyUsageRepository.swift` | ❌ 删除文件 |
| `Database/LocalScanRepository.swift` | `importUsageEvents` 改用行号去重；model_calls insert 改为 token_usages；删 `upsertDailyUsage`；字段映射更新 |

### 3.3 Local Records

| 文件 | 变更 |
|------|------|
| `Core/LocalRecords/LocalUsageModels.swift` | `LocalUsageEvent.sourceTool` → `agenticTool`（或保持 sourceTool 仅在此层用，到 repo 层映射） |
| 三个 Adapter（Pi/Codex/ClaudeCode） | 无需改动（只产出 LocalUsageEvent） |

> **建议**：`LocalUsageEvent` 保持 `sourceTool` 命名，在 `LocalScanRepository.importUsageEvents` 里映射为 `agentic_tool`。避免链式改名扩散。

### 3.4 UI

| 文件 | 变更 |
|------|------|
| `App/AppState.swift` | 删聚合属性（todayCost/todayTokens/todayRequests/todayErrors/todayAvgLatency/monthCost/monthTokens/topProvider/topModel/providerModelStats/modelStats/providerStats/sourceToolStats）；只保留 recentCalls + localSources + pricingRules(只存不展示) |
| `MenuBar/MenuBarView.swift` | 退化为简单列表展示 |
| `Settings/SettingsTab.swift` | 删聚合 tab（请求概览/Models/Providers）；删 Pricing 编辑 UI |
| `Components/UsageUIComponents.swift` | 大幅简化 |

### 3.5 Core

| 文件 | 变更 |
|------|------|
| `Core/CostCalculator.swift` | 保留（pricing_rules 还在，入库时仍需计算 cost） |
| `Core/UsagePresentation.swift` | 删除或大幅简化 |

### 3.6 Tests

| 文件 | 变更 |
|------|------|
| `Tests/.../ModelCallsRepositoryTests.swift` | 改名为 `TokenUsagesRepositoryTests.swift`，测试重写 |
| `Tests/.../DailyUsageRepositoryTests.swift` | ❌ 删除 |
| `Tests/.../AppStateTests.swift` | 重写 |
| `Tests/.../LocalScanRepositoryTests.swift` | 更新去重逻辑测试 |

---

## 4. POC 重建策略

遵循现有 POC 约定（不维护 migration 链）：

1. 直接更新 `v1_initial_schema` 为新 schema
2. `DatabaseManager.resetAndRebuild()` 删除旧 SQLite + 重建
3. 重建后 LocalUsageScanner 重新全量导入 JSONL

---

## 5. 实现顺序

| Step | 内容 | 影响范围 |
|------|------|----------|
| **S1** | 更新 `DatabaseManager.swift`（schema + seed） | 数据库层 |
| **S2** | 重定义 `DomainModels.swift`（TokenUsage + 删聚合类型） | Model 层 |
| **S3** | 创建 `TokenUsagesRepository.swift`（insert + fetchRecent） | Repository 层 |
| **S4** | 更新 `LocalScanRepository.swift`（行号去重 + agentic_tool 映射） | 扫描层 |
| **S5** | 删除 `DailyUsageRepository.swift` | 清理 |
| **S6** | 瘦身 `AppState.swift` | App 状态 |
| **S7** | 简化 UI（MenuBar + Settings + Components） | UI 层 |
| **S8** | 更新/删除测试 | 测试 |
| **S9** | 编译 + 测试通过 | 验收 |

---

## 6. 验收标准

- [ ] `swift build` 成功
- [ ] `swift test` 全部通过
- [ ] 删除旧 SQLite 后启动 App 自动重建 token_usages 表
- [ ] 扫描 JSONL 文件后最近调用列表正确显示
- [ ] 重新扫描同一文件不会重复导入（行号去重生效）
- [ ] `agentic_tool` 列正确填充 codex/claude_code/pi
- [ ] cost_usd 通过 pricing_rules 正常计算
- [ ] MenuBar 和 Settings 无崩溃、无残留聚合 UI
