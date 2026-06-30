## Purpose

从 adapter 解析出的 usage 事件写入 SQLite，通过事件级幂等去重保证计费准确，支持多维度 token 统计和 cost 计算。

## Requirements

### Requirement: Token Usage Recording

系统 MUST 将每个 usage-bearing 事件写入 `token_usages` 表，记录完整的 token 维度信息。

#### Scenario: Usage event imported
- **WHEN** adapter 解析出一个包含 usage 的 LocalUsageEvent
- **THEN** 在 token_usages 表中插入一行，包含：
  - id（唯一标识）
  - agentic_tool（来源工具：codex/claude-code/pi）
  - provider_id（模型提供商）
  - model（模型名称）
  - input_tokens、output_tokens、cached_input_tokens、cache_write_tokens、reasoning_tokens
  - total_tokens（总 token 数）
  - cost_usd（计算出的成本）
  - created_at（事件时间戳）

#### Scenario: Non-usage event received
- **WHEN** adapter 解析出的消息不包含 usage 数据
- **THEN** 该消息可用于解析上下文（如更新 session/provider/model），但不得作为 usage 事件入库

### Requirement: Event-Level Deduplication

系统 MUST 通过 `local_usage_imports` 表保证每个 usage 事件只入库一次。

#### Scenario: Unique event arrives
- **WHEN** 一个之前未导入的 usage 事件到达
- **THEN** 系统在 local_usage_imports 中查找其 key，未找到则插入 usage 和 import 记录

#### Scenario: Duplicate event arrives
- **WHEN** 一个已导入的 usage 事件再次出现（如重复扫描、文件 fork）
- **THEN** 系统在 local_usage_imports 中找到已有 key，跳过该事件，不重复计费

#### Scenario: Stable key generation
- **WHEN** adapter 生成事件的唯一 key
- **THEN** 优先使用源数据的原生稳定 id
- **AND** 若无原生 id，使用 usage 属性的指纹 hash（仅包含 timestamp/provider/model/token/cost 等非敏感字段）

### Requirement: Cross-Line Parse Context

系统 MUST 支持 adapter parse context，以正确关联 usage 事件与其所属的 session、project、provider、model 信息，或保存数据库 source 的 aggregate watermark。

#### Scenario: Context line before usage line
- **WHEN** JSONL 中某行包含 session/cwd/provider/model 信息，后续行包含 usage
- **THEN** 系统将上下文保存在 parse_context_json 中，并在解析 usage 行时应用

#### Scenario: Database aggregate watermark
- **WHEN** SQLite-backed adapter reads cumulative usage aggregates
- **THEN** 系统将每个 session 的非敏感 aggregate watermark 保存在 parse_context_json 中
- **AND** 后续读取 MUST use that watermark to emit only positive usage deltas

#### Scenario: Context only stores non-sensitive metadata
- **WHEN** 保存 parse_context_json
- **THEN** 只允许包含 session id、cwd、provider、model、token aggregate watermark、cost aggregate watermark 等元数据
- **AND** 不得包含 prompt、response、tool output、Authorization、API key

### Requirement: Record-Backed Usage Event Production

系统 MUST import usage events produced from logical usage records through the same `LocalUsageEvent` and repository path regardless of the record backing format.

#### Scenario: JSONL record produces usage
- **WHEN** an append-only JSONL record contains usage-bearing data
- **THEN** the adapter emits `LocalUsageEvent` values using stable non-sensitive keys
- **AND** repository import uses local_usage_imports for event-level deduplication

#### Scenario: SQLite record produces usage
- **WHEN** a SQLite database record contains positive usage deltas
- **THEN** the adapter emits `LocalUsageEvent` values using stable non-sensitive keys
- **AND** repository import uses local_usage_imports for event-level deduplication

#### Scenario: Non-usage record content
- **WHEN** adapter reads content that does not contain usage or positive usage delta
- **THEN** no `token_usages` row is inserted
- **AND** the content MAY update non-sensitive parse context only

### Requirement: Token Dimensions Tracking

token_usages 表 MUST 支持除基础 input/output 外的多维度 token 统计。

#### Scenario: Cached input tokens reported
- **WHEN** usage 事件包含 cached_input_tokens
- **THEN** 系统正确记录 cached_input_tokens 字段

#### Scenario: Reasoning tokens reported
- **WHEN** usage 事件包含 reasoning_tokens（如 o1 等思考模型）
- **THEN** 系统正确记录 reasoning_tokens 字段

#### Scenario: Cache write tokens reported
- **WHEN** usage 事件包含 cache_write_tokens
- **THEN** 系统正确记录 cache_write_tokens 字段

### Requirement: Cost Calculation

系统 MUST 根据 model 表的价格信息和 usage 的 token 维度计算每次使用的成本。

#### Scenario: Model price found
- **WHEN** usage 事件的 provider/model 在 models 表中有对应价格
- **THEN** cost_usd = input_tokens × input_price + output_tokens × output_price + cached_input_tokens × cached_input_price + reasoning_tokens × reasoning_price

#### Scenario: Model price not found
- **WHEN** usage 事件的 provider/model 在 models 表中没有对应价格
- **THEN** cost_usd 设为 0
