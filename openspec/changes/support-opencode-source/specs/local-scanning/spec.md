## MODIFIED Requirements

### Requirement: Built-in Source Discovery

系统必须在启动时自动扫描 Codex、Claude Code、pi、OpenCode 的默认本地记录位置。这些 source 始终启用，用户无需手动配置。

- Codex: `~/.codex/sessions/**/*.jsonl`
- Claude Code: `~/.claude/projects/**/*.jsonl`
- pi: `~/.pi/agent/sessions/**/*.jsonl`
- OpenCode: `~/.local/share/opencode/opencode.db`

#### Scenario: All directories exist

- **WHEN** 应用启动且所有默认 source 位置均存在
- **THEN** 系统为每个 source 启动 catch-up 扫描和 FSEvents 监听

#### Scenario: Directory does not exist

- **WHEN** 某个 agent 的默认目录或数据库不存在
- **THEN** 系统不报错，对应 source 状态标记为 unavailable
- **AND** 该位置后续出现时系统应能重新检测并开始扫描

## ADDED Requirements

### Requirement: Unified Session Source Interface

系统必须通过同一个 session source 监控接口处理所有内置 source，无论底层记录格式是 JSONL 文件还是 SQLite 数据库。

#### Scenario: Existing JSONL source changes

- **WHEN** Codex、Claude Code 或 pi 的 JSONL session 记录发生变化
- **THEN** 系统通过统一 source 接口发现变更、读取新增 usage、更新 checkpoint 并导入 usage 事件
- **AND** 系统保持现有 JSONL 增量读取、parse context、半行保护和去重行为不变

#### Scenario: OpenCode SQLite source changes

- **WHEN** OpenCode SQLite session 记录发生变化
- **THEN** 系统通过同一个 source 接口发现变更、读取 session usage 增量、更新 checkpoint 并导入 usage 事件

#### Scenario: Source backing store differs

- **WHEN** 不同 source 使用不同底层存储格式
- **THEN** scanner、background service、import queue 和 repository 不得为 OpenCode 使用独立的并行导入管线
- **AND** 只有 adapter 内部负责把各自底层记录格式转换为 LocalUsageEvent

### Requirement: OpenCode SQLite Source Scanning

系统必须从 OpenCode 本地 SQLite 数据库读取 session 级 usage 聚合数据，并将其作为 `opencode` source 的 usage 事件导入。

#### Scenario: OpenCode database exists with usage-bearing sessions

- **WHEN** `~/.local/share/opencode/opencode.db` 存在且 `session` 表中存在带 token 或 cost 聚合值的记录
- **THEN** 系统读取 session id、directory、model、time_created、time_updated、cost、tokens_input、tokens_output、tokens_reasoning、tokens_cache_read、tokens_cache_write
- **AND** 系统为每个有正向 usage 增量的 session 导入 `opencode` usage 事件

#### Scenario: OpenCode session aggregate increases

- **WHEN** 同一个 OpenCode session 的 token 或 cost 聚合值在上次导入后增加
- **THEN** 系统只导入新增的正向增量
- **AND** 系统更新该 session 的扫描水位以避免后续重复计费

#### Scenario: OpenCode session aggregate unchanged

- **WHEN** OpenCode session 的 token 和 cost 聚合值与上次导入时相同
- **THEN** 系统不导入新的 usage 事件

#### Scenario: OpenCode database sidecar changes

- **WHEN** FSEvents 报告 `opencode.db`、`opencode.db-wal`、`opencode.db-shm` 或 OpenCode 数据目录变化
- **THEN** 系统将变化归一化为对 `opencode.db` 的重新扫描

#### Scenario: OpenCode schema unsupported

- **WHEN** OpenCode 数据库缺少读取 usage 所需的 `session` 表或字段
- **THEN** 系统记录脱敏后的 parse error 状态
- **AND** 系统不得导入部分或猜测的 usage 数据

#### Scenario: OpenCode privacy boundary

- **WHEN** 扫描 OpenCode 数据库
- **THEN** 系统不得读取或保存 message、part、event、todo、account、auth、tool output、prompt、response、tool output、Authorization 或 API key 内容
