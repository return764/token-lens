## MODIFIED Requirements

### Requirement: Token Usage Recording

系统必须将每个 usage-bearing 事件写入 `token_usages` 表，记录完整的 token 维度信息。

#### Scenario: Usage event imported

- **WHEN** adapter 解析出一个包含 usage 的 LocalUsageEvent
- **THEN** 在 token_usages 表中插入一行，包含：
  - id（唯一标识）
  - agentic_tool（来源工具：codex/claude-code/pi/opencode）
  - provider_id（模型提供商）
  - model（模型名称）
  - input_tokens、output_tokens、cached_input_tokens、cache_write_tokens、reasoning_tokens
  - total_tokens（总 token 数）
  - cost_usd（源提供或计算出的成本）
  - created_at（事件时间戳）

#### Scenario: Non-usage event received

- **WHEN** adapter 解析出的消息不包含 usage 数据
- **THEN** 该消息可用于解析上下文（如更新 session/provider/model），但不得作为 usage 事件入库

## ADDED Requirements

### Requirement: Source-Provided Cost Preservation

系统必须优先保留 source 已提供的 usage cost，并仅在 source 未提供 cost 时使用本地价格表计算。

#### Scenario: Usage event has source-provided cost

- **WHEN** LocalUsageEvent 包含 costUsd
- **THEN** 系统将该 costUsd 写入 token_usages.cost_usd
- **AND** 系统不得用 model 表价格覆盖该值

#### Scenario: Usage event has no source-provided cost

- **WHEN** LocalUsageEvent 不包含 costUsd
- **THEN** 系统根据 provider、model 和 token 维度使用 model 表价格计算 cost_usd
