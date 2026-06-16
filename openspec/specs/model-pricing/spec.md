## Purpose

从 models.dev 公开 API 初始化本地模型价格表，为 usage 的 cost 计算提供价格基准。

## Requirements

### Requirement: Price Initialization from models.dev

系统必须在首次启动或 models 表为空时，从 `https://models.dev/api.json` 获取模型价格数据并写入本地。

#### Scenario: First launch with empty models table
- **WHEN** 应用首次启动且 models 表为空
- **THEN** 系统请求 models.dev API 获取价格数据
- **AND** 将返回的模型价格写入 models 表

#### Scenario: Network unavailable during first launch
- **WHEN** 首次启动但 models.dev 不可访问
- **THEN** 系统不阻塞启动，models 表保持为空
- **AND** 后续所有 usage 的 cost_usd 设为 0（因为无价格可查）
- **AND** 系统应在网络恢复后重试价格初始化

#### Scenario: Subsequent launches with existing data
- **WHEN** 应用启动且 models 表已有数据
- **THEN** 系统不重新请求 models.dev
- **AND** 直接使用本地价格数据计算 cost

### Requirement: Price Data Schema

models 表必须存储完整的模型价格信息以支持多维度 cost 计算。

#### Scenario: Model price record created
- **WHEN** 从 models.dev 获取到一个模型的价格信息
- **THEN** 在 models 表中创建记录，包含：
  - id（唯一标识）
  - provider_id（提供商，如 openai/anthropic/google）
  - model（模型名称）
  - input_price、output_price、cached_input_price、reasoning_price（per-token 价格）
  - currency（固定为 USD）
  - effective_from、effective_to（价格有效期）
  - created_at（记录创建时间）

#### Scenario: Multiple providers supported
- **WHEN** models.dev 返回多家提供商的模型价格
- **THEN** 系统正确区分 provider_id 并全部写入
- **AND** 支持通过 provider_id + model 组合查找价格

### Requirement: Price Lookup for Cost Calculation

系统必须通过 provider_id 和 model 精确匹配价格，用于 usage 事件的 cost 计算。

#### Scenario: Exact match found
- **WHEN** usage 事件的 provider_id 和 model 在 models 表中有匹配
- **THEN** 返回对应的 input_price、output_price、cached_input_price、reasoning_price

#### Scenario: No match found
- **WHEN** usage 事件的 provider_id 或 model 在 models 表中无匹配
- **THEN** cost 计算结果为 0（而非报错或使用默认价格）
