## Purpose

自动发现并持续监听本地 agent 工具的 JSONL 会话日志，增量读取 usage 数据，管理文件级 checkpoint。

## Requirements

### Requirement: Built-in Source Discovery

系统必须在启动时自动扫描 Codex、Claude Code、pi 的默认 JSONL 目录。这些 source 始终启用，用户无需手动配置。

- Codex: `~/.codex/sessions/**/*.jsonl`
- Claude Code: `~/.claude/projects/**/*.jsonl`
- pi: `~/.pi/agent/sessions/**/*.jsonl`

#### Scenario: All directories exist
- **WHEN** 应用启动且所有默认目录均存在
- **THEN** 系统为每个 source 启动 catch-up 扫描和 FSEvents 监听

#### Scenario: Directory does not exist
- **WHEN** 某个 agent 的默认目录不存在
- **THEN** 系统不报错，对应 source 状态标记为 unavailable
- **AND** 该目录后续出现时系统应能重新检测并开始扫描

### Requirement: Catch-up Scan on Startup

系统必须在启动时对已存在的 JSONL 文件进行全量 catch-up 扫描，导入历史 usage 数据。

#### Scenario: Fresh startup with existing JSONL files
- **WHEN** 应用启动且有未导入的 JSONL 文件
- **THEN** 系统扫描所有匹配的 JSONL 文件并导入 usage 事件
- **AND** 自动跳过已通过 local_usage_imports 去重的重复事件

#### Scenario: Subsequent startups
- **WHEN** 应用再次启动且上次已扫描完成
- **THEN** 系统仅导入自上次扫描以来新增的 usage 事件

### Requirement: Incremental File Reading

系统必须逐行增量读取 JSONL 文件，通过 `local_scan_files` 表记录每个文件的读取偏移量和解析上下文。

#### Scenario: New JSONL content appended
- **WHEN** 被监听的 JSONL 文件新增完整行
- **THEN** 系统从上次记录的 read_offset 继续读取新行并解析

#### Scenario: Partial write (half line)
- **WHEN** JSONL 文件中存在不完整的行（无尾随换行符）
- **THEN** 系统不解析该行，等待下一次文件变化事件后再读取完整行

#### Scenario: File truncation or rotation
- **WHEN** 被监听的 JSONL 文件被截断或轮转
- **THEN** 系统重置 read_offset 为 0 并重新读取整个文件
- **AND** 已导入的事件通过 local_usage_imports 去重保证不被重复计费

### Requirement: FSEvents-based File Watching

系统必须通过 FSEvents 监听每个 source 的 root 目录，实时捕获文件新增和修改事件。

#### Scenario: New JSONL file created
- **WHEN** 监听目录下创建新的 JSONL 文件
- **THEN** 系统捕获事件并将该文件加入增量读取队列

#### Scenario: Duplicate or overlapping watcher events
- **WHEN** FSEvents 对同一文件触发多次或重叠的事件
- **THEN** 系统通过文件偏移量记录和 local_usage_imports 去重保证不重复扫描重复计费

#### Scenario: Periodic reconcile as fallback
- **WHEN** 正常监听中
- **THEN** 系统定期进行 reconcile 扫描兜底，确保不遗漏因 FSEvents 丢失导致未被处理的事件

### Requirement: File Checkpoint Management

系统必须通过 `local_scan_files` 表持久化每个文件的扫描状态。

#### Scenario: File checkpoint created on first scan
- **WHEN** 系统首次扫描一个 JSONL 文件
- **THEN** 在 local_scan_files 中创建记录，包含 path、read_offset、file_id、modified_at

#### Scenario: Checkpoint updated after incremental read
- **WHEN** 增量读取完成后
- **THEN** 更新 read_offset、file_size、modified_at、file_id、imported_event_count

#### Scenario: Parse context preserved
- **WHEN** JSONL 解析器在处理跨行上下文（如 session id、cwd、provider、model）
- **THEN** 系统将上下文保存到 parse_context_json 字段用于后续行的解析

### Requirement: Source Status Tracking

系统必须在 `local_scan_sources` 表中记录每个 source 的扫描状态和统计信息。

#### Scenario: Scan starts
- **WHEN** 系统开始扫描某个 source
- **THEN** 更新 status 为 scanning 并记录 last_scan_started_at

#### Scenario: Scan completes
- **WHEN** 扫描完成
- **THEN** 更新 status 为 ready，记录 last_scan_finished_at 和统计数据（files_seen、files_scanned、events_imported）

#### Scenario: Parse error occurs
- **WHEN** 某行 JSONL 解析失败
- **THEN** 递增 parse_error_count，记录脱敏后的 last_error 信息
- **AND** 不回显原始 JSONL 内容
