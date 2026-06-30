## MODIFIED Requirements

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

## ADDED Requirements

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
