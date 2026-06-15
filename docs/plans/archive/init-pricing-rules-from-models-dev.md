# 首次启动时从 models.dev/api.json 初始化 models 表

> 状态：**Completed / Archived** — 2026-06-15  
> 最后更新：2026-06-15

## 1. 背景

TokenLens 当前使用 `models` 表保存模型价格，用于 `CostCalculator` 计算 token usage 成本。价格数据来自公开 API：`https://models.dev/api.json`。

历史上的硬编码少量价格 seed 已移除；当前不再使用 `pricing_rules` 表名，代码中保留 `PricingRule` 领域模型作为价格规则结构。

## 2. 当前行为

| 决策 | 当前实现 |
|---|---|
| Provider 映射 | 不映射，直接使用 API 返回的 provider slug 作为 `provider_id` |
| 拉取时机 | `models` 表为空时拉取 |
| 触发位置 | `AppState` 初始化 Task 中调用 `ModelsSeeder.seedIfNeeded()` |
| 成功策略 | `ModelsRepository.replaceAll(rules)`，然后写入 `settings.last_synced_at = now` |
| 失败策略 | 清空 `models` 表，并写入 `settings.last_synced_at = failed` |
| 无 cost 的 model | 跳过 |
| 无匹配价格 | `CostCalculator` 返回 `costUsd = 0`, `pricingFound = false` |

## 3. 当前 Schema

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

CREATE INDEX IF NOT EXISTS idx_models_provider_model
ON models(provider_id, model);
```

## 4. API 数据结构

`https://models.dev/api.json` 返回：

```json
{
  "<provider_slug>": {
    "id": "<provider_slug>",
    "name": "Provider Display Name",
    "models": {
      "<model_id>": {
        "id": "<model_id>",
        "name": "Model Display Name",
        "cost": {
          "input": 2.50,
          "output": 10.00,
          "cache_read": 1.25
        }
      }
    }
  }
}
```

字段映射：

| API 字段 | `PricingRule` 字段 | `models` 列 |
|---|---|---|
| provider slug | `providerId` | `provider_id` |
| `model.id` | `model` | `model` |
| `cost.input` | `inputPrice` | `input_price` |
| `cost.output` | `outputPrice` | `output_price` |
| `cost.cache_read` | `cachedInputPrice` | `cached_input_price` |
| — | `reasoningPrice` | `reasoning_price`（当前默认 0） |

## 5. 当前数据流

```text
AppState init
  ↓
ModelsSeeder.seedIfNeeded()
  ↓
ModelsRepository.fetchAll()
  ├─ 非空：跳过
  └─ 空：ModelsDevAPIService.fetchProviders()
        ├─ 失败：deleteAll + settings.last_synced_at = failed
        └─ 成功：buildRules(from response)
              ↓
           ModelsRepository.replaceAll(rules)
              ↓
           settings.last_synced_at = now
```

## 6. 当前实现文件

| 文件 | 职责 |
|---|---|
| `Models/ModelsDevAPIModels.swift` | API Decodable models |
| `Services/ModelsDevAPIService.swift` | `ModelsDevAPI` protocol + URLSession implementation |
| `Services/ModelsSeeder.swift` | seedIfNeeded、规则构建、失败策略 |
| `Database/ModelsRepository.swift` | find/fetchAll/deleteAll/replaceAll |
| `Core/CostCalculator.swift` | 使用 `ModelsRepository.find` 计算费用 |
| `App/AppState.swift` | App 启动时触发 seed |

## 7. 当前核心实现摘要

```swift
public protocol ModelsDevAPI {
    func fetchProviders() async throws -> ModelsDevResponse
}

public final class ModelsSeeder {
    public init(api: ModelsDevAPI,
                modelsRepo: ModelsRepository,
                settingsRepo: SettingsRepository)

    public func seedIfNeeded() async throws
}
```

`ModelsSeeder.buildRules` 会：

1. 遍历 provider/model。
2. 跳过 `cost == nil` 的 model。
3. 用 `providerSlug + modelId` 生成稳定 id，并对 `/ : .` 做安全替换。
4. 对 id 冲突去重。
5. 默认 `effectiveFrom = "2025-01-01"`，`currency = "USD"`。

## 8. 测试覆盖

相关测试：

- `ModelsRepositoryBatchTests`
- `ModelsSeederTests`
- `CostCalculatorTests`

当前 `swift test`：80 tests, 0 failures。

## 9. 后续可改进

- Settings 中展示同步状态与失败原因。
- 提供手动刷新价格按钮。
- 周期刷新 models.dev 数据。
- 对 provider/model alias 做更智能匹配。
