## Purpose

自动发现并持续监听本地 agent 工具的 local usage records，增量读取 usage 数据，管理 record-level checkpoint。

## Requirements

### Requirement: Built-in Source Discovery

系统 MUST 在启动时自动扫描 Codex、Claude Code、pi、OpenCode 的默认本地记录位置。这些 source 始终启用，用户无需手动配置。

- Codex: `~/.codex/sessions/**/*.jsonl`
- Claude Code: `~/.claude/projects/**/*.jsonl`
- pi: `~/.pi/agent/sessions/**/*.jsonl`
- OpenCode: `~/.local/share/opencode/opencode.db`

每个 source 的 adapter MUST discover logical usage records, not raw parser-specific file URLs.

#### Scenario: All source locations exist
- **WHEN** 应用启动且所有默认 source 位置均存在
- **THEN** 系统为每个 source 发现 logical usage records
- **AND** 系统为每个 source 启动 catch-up 扫描和 FSEvents 监听

#### Scenario: Source location does not exist
- **WHEN** 某个 agent 的默认目录或数据库不存在
- **THEN** 系统不报错，对应 source 状态标记为 unavailable
- **AND** 该位置后续出现时系统应能重新检测并开始扫描

### Requirement: Catch-up Scan on Startup

系统 MUST 在启动时对已存在的 logical usage records 进行 catch-up 扫描，导入历史 usage 数据。

#### Scenario: Fresh startup with existing records
- **WHEN** 应用启动且有未导入的 local usage records
- **THEN** 系统扫描所有 adapter 发现的 records 并导入 usage 事件
- **AND** 自动跳过已通过 local_usage_imports 去重的重复事件

#### Scenario: Subsequent startups
- **WHEN** 应用再次启动且上次已扫描完成
- **THEN** 系统仅导入自上次扫描以来新增的 usage 事件

### Requirement: Incremental File Reading

系统 MUST 增量读取 append-only JSONL records，并通过 `local_scan_files` 表记录每个 logical record 的读取偏移量和解析上下文。

#### Scenario: New JSONL content appended
- **WHEN** 被监听的 JSONL record 新增完整行
- **THEN** 系统从上次记录的 read_offset 继续读取新行并解析

#### Scenario: Partial write (half line)
- **WHEN** JSONL record 中存在不完整的行（无尾随换行符）
- **THEN** 系统不解析该行，等待下一次文件变化事件后再读取完整行

#### Scenario: File truncation or rotation
- **WHEN** 被监听的 JSONL record 被截断或轮转
- **THEN** 系统重置 read_offset 为 0 并重新读取整个 record
- **AND** 已导入的事件通过 local_usage_imports 去重保证不被重复计费

### Requirement: FSEvents-based File Watching

系统 MUST 通过 FSEvents 监听每个 source 的 root 目录，实时捕获文件新增和修改事件，并由 adapter 将 changed paths 归一化为 logical usage records。

#### Scenario: New JSONL file created
- **WHEN** 监听目录下创建新的 JSONL session 文件
- **THEN** 对应 adapter 将该文件归一化为 append-only JSONL record
- **AND** 系统将该 record 加入增量读取队列

#### Scenario: SQLite sidecar file changes
- **WHEN** FSEvents 报告 `opencode.db`、`opencode.db-wal`、`opencode.db-shm` 或 OpenCode 数据目录变化
- **THEN** OpenCode adapter MUST normalize the change to the main `opencode.db` logical record
- **AND** 系统不得为 WAL 或 SHM sidecar 创建独立 checkpoint record

#### Scenario: Duplicate or overlapping watcher events
- **WHEN** FSEvents 对同一 logical record 触发多次或重叠的事件
- **THEN** 系统通过 record checkpoint、队列去重和 local_usage_imports 去重保证不重复扫描重复计费

#### Scenario: Periodic reconcile as fallback
- **WHEN** 正常监听中
- **THEN** 系统定期通过 adapter discover logical usage records 进行 reconcile 扫描兜底
- **AND** 系统确保不遗漏因 FSEvents 丢失导致未被处理的事件

### Requirement: File Checkpoint Management

系统 MUST 通过 `local_scan_files` 表持久化每个 logical usage record 的扫描状态。

#### Scenario: Record checkpoint created on first scan
- **WHEN** 系统首次扫描一个 logical usage record
- **THEN** 在 local_scan_files 中创建记录，path MUST equal `record.checkpointURL.path`
- **AND** 记录包含 read_offset、file_id、modified_at

#### Scenario: Checkpoint updated after incremental read
- **WHEN** 增量读取完成后
- **THEN** 更新 read_offset、file_size、modified_at、file_id、imported_event_count

#### Scenario: Parse context preserved
- **WHEN** adapter 在处理跨行上下文或数据库 aggregate watermark
- **THEN** 系统将上下文保存到 parse_context_json 字段用于后续读取

#### Scenario: Sidecar path maps to main checkpoint
- **WHEN** SQLite sidecar path 触发导入
- **THEN** checkpoint MUST be read and written using the main database record checkpoint path

### Requirement: Source Status Tracking

系统 MUST 在 `local_scan_sources` 表中记录每个 source 的扫描状态和统计信息。

#### Scenario: Scan starts
- **WHEN** 系统开始扫描某个 source
- **THEN** 更新 status 为 scanning 并记录 last_scan_started_at

#### Scenario: Scan completes
- **WHEN** 扫描完成
- **THEN** 更新 status 为 ready，记录 last_scan_finished_at 和统计数据（files_seen、files_scanned、events_imported）

#### Scenario: Parse error occurs
- **WHEN** 某个 record 解析失败
- **THEN** 递增 parse_error_count，记录脱敏后的 last_error 信息
- **AND** 不回显原始 JSONL、SQLite content 或敏感内容

### Requirement: Record-Oriented Local Usage Adapter

系统 MUST define `LocalUsageAdapter` as a record-oriented source interface. The adapter protocol MUST expose only source metadata, record discovery, changed-path candidate normalization, and usage-change reading.

#### Scenario: Adapter discovers records
- **WHEN** scanner asks an adapter for work
- **THEN** adapter returns `LocalUsageRecord` values containing read URL, checkpoint URL, display path, and record kind

#### Scenario: Adapter reads usage changes
- **WHEN** scanner or import queue has a candidate record
- **THEN** it calls `readUsageChanges(record:checkpoint:)`
- **AND** the result contains usage events, checkpoint update, observed size, and re-enqueue hint

#### Scenario: Adapter protocol has no JSONL-only compatibility methods
- **WHEN** implementing a `LocalUsageAdapter`
- **THEN** the protocol MUST NOT require `discoverFiles`, `checkpointURL(for:)`, `readSessionChanges(file:checkpoint:)`, `parseFile`, `bootstrapContext`, or `parseLines`

### Requirement: Append-Only JSONL Reader Helper

系统 MUST keep append-only JSONL incremental behavior in a shared helper used by JSONL-backed adapters.

#### Scenario: JSONL adapter reads a record
- **WHEN** Codex、Claude Code 或 pi adapter reads an append-only JSONL record
- **THEN** the adapter uses the shared JSONL helper to read complete new lines, preserve offset semantics, update parse context, and build a checkpoint update

#### Scenario: JSONL parser is source-specific
- **WHEN** the shared JSONL helper has read complete lines
- **THEN** source-specific decoder logic determines whether each line updates context, emits usage, or is ignored

### Requirement: Logical Record Queue Deduplication

系统 MUST deduplicate pending and in-progress import work by source id and logical record checkpoint path.

#### Scenario: Multiple paths map to one record
- **WHEN** changed paths include both `opencode.db` and `opencode.db-wal`
- **THEN** import queue enqueues one logical OpenCode database record
- **AND** no concurrent duplicate import runs for the same source id and checkpoint path

#### Scenario: Re-enqueue uses logical record
- **WHEN** a read result indicates more changes may remain
- **THEN** import queue re-enqueues the same logical record, not the original changed path
