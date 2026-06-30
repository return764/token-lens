# LocalUsageAdapter 接口重设计计划

## 背景

当前 `LocalUsageAdapter` 已经有统一的 `readSessionChanges(file:checkpoint:)`，扫描器和导入队列也主要通过它读取增量 usage。但协议仍强制暴露 `parseFile`、`bootstrapContext`、`parseLines` 等 JSONL 专属接口，导致：

- pi / Claude Code / Codex 适配自然，因为它们都是 append-only JSONL。
- OpenCode 是 SQLite 数据源，只能实现空的 `parseLines`，接口语义不干净。
- `discoverFiles()` 和 `candidates(fromChangedPaths:)` 都返回裸 `URL`，无法表达“监听 WAL，但 checkpoint 归一到主库”这类逻辑记录。
- OpenCode 当前把 `opencode.db`、`opencode.db-wal`、`opencode.db-shm` 都作为发现文件，虽然 `checkpointURL` 会归一，但启动扫描和 reconcile 会有重复读取空间。

目标是把 adapter 从“JSONL parser”重塑成“本地 usage 记录源”，显式支持三类模式：

1. pi 模式：固定目录下 `session.jsonl`，append message，每条 usage-bearing message 自带 usage。
2. Codex 模式：固定目录下 `session.jsonl`，append message，但一轮结束时有专门 usage JSON object。
3. OpenCode 模式：固定目录下 SQLite DB 保存 session/message 信息，需要响应 `opencode.db-wal` 变化并从 DB 读 usage delta。

## 设计原则

- Scanner / queue 只知道“发现记录、把文件系统事件归一成记录、读取 usage changes”，不关心 JSONL 或 SQLite。
- JSONL 增量读取、行上下文、完整行边界处理仍作为共享 helper 保留，但不再是 adapter 协议的必选能力。
- 一个“逻辑记录”必须有稳定 checkpoint key。OpenCode 的 WAL/SHM 事件应归一到主 DB 的 checkpoint key。
- `parse_context_json` 继续只存非敏感状态：session id、cwd、provider/model、usage aggregate watermark 等，不存 prompt/response/tool output。
- 沿用现有 `token_usages`、`local_usage_imports`、`local_scan_sources`、`local_scan_files` 表，优先不做数据库迁移。

## 目标接口形状

新增逻辑记录类型，替代裸 `URL` 在 adapter 边界内传递：

```swift
public struct LocalUsageRecord: Equatable, Hashable {
    public let readURL: URL          // 真正读取的文件，如 session.jsonl 或 opencode.db
    public let checkpointURL: URL    // local_scan_files.path 使用的稳定 key
    public let displayPath: String   // 日志/UI 展示路径，默认 readURL.path
    public let kind: LocalUsageRecordKind
}

public enum LocalUsageRecordKind: Equatable, Hashable {
    case appendOnlyJSONL
    case sqliteDatabase
}
```

重设计后的 `LocalUsageAdapter` 只保留源级元数据、发现/归一、读取：

```swift
public protocol LocalUsageAdapter {
    var id: String { get }
    var displayName: String { get }
    var defaultRoot: URL { get }

    func discoverRecords() throws -> [LocalUsageRecord]
    func candidates(fromChangedPaths paths: [URL]) throws -> [LocalUsageRecord]
    func readUsageChanges(
        record: LocalUsageRecord,
        checkpoint: LocalScanFileCheckpoint?
    ) throws -> LocalUsageSessionReadResult
}
```

旧接口直接移除：`discoverFiles()`、`checkpointURL(for:)`、`readSessionChanges(file:checkpoint:)`、`parseFile(_:)`、`bootstrapContext(file:checkpoint:)`、`parseLines(_:file:context:)` 都不再属于 `LocalUsageAdapter`。Scanner / import queue 只使用 `LocalUsageRecord` 和 `readUsageChanges(record:checkpoint:)`。

## JSONL 模式抽象

增加一个共享 reader/helper，例如 `AppendOnlyJSONLUsageReader`，负责：

- 用 `LocalJSONLIncrementalReader` 从 checkpoint offset 读取完整新行。
- 处理文件截断/rotate。
- 调用 source-specific JSON object parser。
- 回写 `LocalScanFileCheckpointUpdate`，包括 offset、fileSize、modifiedAt、parseContext。

JSONL adapter 只实现解析语义：

```swift
protocol JSONLUsageEventDecoder {
    var id: String { get }
    func initialContext(
        record: LocalUsageRecord,
        checkpoint: LocalScanFileCheckpoint?
    ) throws -> LocalUsageParseContext?

    func parseJSONLLines(
        _ lines: [(lineNumber: Int?, text: String)],
        record: LocalUsageRecord,
        context: inout LocalUsageParseContext?
    ) throws -> [LocalUsageEvent]
}
```

### pi 模式

- `discoverRecords()` 扫描 `~/.pi/agent/sessions/**/*.jsonl`。
- `candidates(fromChangedPaths:)` 复用 JSONL 路径扩展逻辑。
- parser 遇到 session/meta line 时更新 context；遇到 assistant message 且 `message.usage` 存在时立即产出 `LocalUsageEvent`。
- usage event key 继续使用原生 message id；没有 id 时使用非敏感 usage 指纹。

### Codex 模式

- `discoverRecords()` 扫描 `~/.codex/sessions/**/*.jsonl`。
- `candidates(fromChangedPaths:)` 同 JSONL。
- parser 先 ingest `session_meta` / `turn_context` 等上下文行；只有遇到 `event_msg` + `payload.type == token_count` 时产出 usage event。
- 若 checkpoint 有 offset 但没有 context，`initialContext` 可以读取 offset 前内容重建 session/cwd/provider/model，上层无需知道这个细节。

## SQLite 模式抽象

OpenCode 不走 JSONL helper，直接实现 `readUsageChanges(record:checkpoint:)`：

- `discoverRecords()` 只返回一个逻辑记录：`opencode.db`，如果主库存在。
- `candidates(fromChangedPaths:)` 将以下变化归一到同一个 `LocalUsageRecord(readURL: opencode.db, checkpointURL: opencode.db)`：
  - root 目录变化
  - `opencode.db`
  - `opencode.db-wal`
  - `opencode.db-shm`
- 读取时使用 GRDB read-only 打开主库，依赖 SQLite snapshot 读取 WAL 中已提交内容。
- 查询只允许 session usage aggregate 所需列，不读取 message body、prompt、response、tool output、auth。
- `parse_context_json` 保存 per-session aggregate watermark。
- 本次 aggregate 相对 checkpoint 有正向 delta 时产出事件；aggregate 下降时按 reset/fork 处理，导入当前正值并替换 watermark。
- `readOffset` 对 SQLite 无业务意义，可继续设为当前 DB file size；真正的增量水位在 parse context 中。

## Scanner / Queue 调整

1. `LocalUsageScanner.scan(_:)`
   - 调用 `adapter.discoverRecords()`。
   - 用 `record.checkpointURL.path` 查 checkpoint。
   - 调用 `adapter.readUsageChanges(record:checkpoint:)`。
   - file status 的 path 使用 `record.checkpointURL.path`，展示/log 可用 `record.displayPath`。

2. `LocalSourceImportQueue`
   - pending key 从 `"tool::path"` 改成 `"tool::checkpointPath"`，避免 WAL 和 DB 事件重复并发导入。
   - 只保留 `enqueue(sourceTool:records:)`。

3. `LocalSourcesBackgroundService`
   - FSEvents 仍 watch `adapter.defaultRoot`。
   - 回调里调用 `adapter.candidates(fromChangedPaths:)`，拿到逻辑记录后 enqueue。
   - periodic reconcile 调用 `discoverRecords()`，再用 `record.checkpointURL` 判断是否需要扫描。

## 实施步骤

1. 新增 `LocalUsageRecord` / `LocalUsageRecordKind`。
2. 将 `LocalUsageAdapter` 改成最终协议，只包含 `discoverRecords`、`candidates`、`readUsageChanges(record:checkpoint:)`。
3. 删除协议 extension 中的 JSONL 默认读取逻辑，新增 `AppendOnlyJSONLUsageReader`。
4. 将 scanner、import queue、background service 全部改为 `LocalUsageRecord` 路径。
5. 将 Pi / Claude Code / Codex 改为 JSONL record adapter：`discoverRecords + parseJSONLLines`。
6. 将 OpenCode 改为 SQLite record adapter：只 discover 主 DB，WAL/SHM 只作为 candidate trigger。
7. 删除 OpenCode 的空 `parseLines` 实现，并删除所有旧 `parseFile` / `parseLines` / `readSessionChanges` 测试 stub。
8. 更新文档 `docs/adding-new-local-source.md` 和 `PROJECT_SPEC.md`，把 adapter 分类写清楚。

## 测试计划

- JSONL reader 增量测试保持不变：完整行、半行、截断/rotate、offset 更新。
- Pi adapter：
  - message 自带 usage 时立即产出 event。
  - session id / cwd 从前文 context 继承。
- Codex adapter：
  - `token_count` object 才产出 event。
  - checkpoint 缺 context 时能从 offset 前内容 bootstrap。
- OpenCode adapter：
  - `discoverRecords()` 只返回 `opencode.db`。
  - `opencode.db-wal` 变化归一为主 DB record。
  - cumulative aggregate 只导入 delta，不重复计费。
  - schema 缺列时报 sanitized parse error。
- Scanner / queue：
  - 使用 `record.checkpointURL` 查 checkpoint。
  - WAL 和 DB 同时触发时只并发导入一次。
  - catch-up scan、watcher import、periodic reconcile 三条路径都走 `readUsageChanges(record:)`。
- 隐私测试：
  - OpenCode 不查询 message/prompt/content/tool output 相关表。
  - JSONL key/context 不包含消息原文。

## 验收标准

- `swift test` 全绿。
- Codex / pi / Claude Code 现有导入行为不变。
- OpenCode 启动扫描只扫描主 DB 一次。
- OpenCode 写入 WAL 时能触发导入，checkpoint 仍落在 `opencode.db`。
- 重复文件事件、重复扫描、DB/WAL 同时变化不会重复计费。
- 主协议不再要求 SQLite adapter 实现 JSONL-only 方法。

## 风险与取舍

- 协议迁移会影响测试 stub。直接改测试，避免保留双接口带来的长期噪音。
- `LocalUsageRecord` 会让 scanner/queue 改动稍多，但能换来 checkpoint、watch trigger、read target 的清晰边界。
- SQLite aggregate 模式无法知道“单条 message usage”，只能依据 OpenCode 暴露的 session aggregate 导入 delta；这是当前数据源的自然限制。
- 如果未来出现“目录内多 DB”或“非文件事件源”，`LocalUsageRecord` 仍可扩展，不需要把 scanner 再拆一条专用通道。
