# Context-aware Incremental Parser Plan

> 状态：✅ Completed  
> 最后更新：2026-06-13

## 1. 目标

让本地 JSONL adapter 在增量读取时仍能保留跨行上下文（session id、cwd、provider、model 等），避免每次文件变化都全文件解析。

当前已实现：`LocalUsageAdapter.parseLines(..., context:)` + `local_scan_files.parse_context_json`。

## 2. 当前接口

定义在 `Sources/TokenLensApp/Core/LocalRecords/LocalUsageModels.swift`：

```swift
public struct LocalUsageParseContext: Equatable {
    public let sourceTool: String
    public var json: String
}

public protocol LocalUsageAdapter {
    var id: String { get }
    var displayName: String { get }
    var defaultRoot: URL { get }

    func discoverFiles() throws -> [URL]
    func parseFile(_ url: URL) throws -> [LocalUsageEvent]
    func bootstrapContext(
        file: URL,
        checkpoint: LocalScanFileCheckpoint?
    ) throws -> LocalUsageParseContext?
    func parseLines(
        _ lines: [(lineNumber: Int?, text: String)],
        file: URL,
        context: inout LocalUsageParseContext?
    ) throws -> [LocalUsageEvent]
}
```

默认 `bootstrapContext` 返回 checkpoint 中已有 context。不需要跨行上下文的 adapter 可以保持 stateless。

## 3. 当前 DB 支持

`local_scan_files` 包含：

```sql
parse_context_json TEXT
```

Repository 类型包含：

- `LocalScanFileCheckpoint.parseContext`
- `LocalScanFileCheckpointUpdate.parseContext`

`LocalScanRepository.importIncrementalUsageEvents` 在同一 transaction 内：

1. 使用 `local_usage_imports.key` 去重。
2. 插入 `token_usages`。
3. 更新 `read_offset`。
4. 更新 `parse_context_json`。

## 4. 当前导入流程

```swift
let checkpoint = try repository.checkpoint(for: adapter.id, path: file.path)
var context = try adapter.bootstrapContext(file: file, checkpoint: checkpoint)
let batch = try incrementalReader.readNewLines(url: file, from: checkpoint?.readOffset ?? 0)
let events = try adapter.parseLines(batch.lines, file: file, context: &context)
try repository.importIncrementalUsageEvents(events, checkpoint: .init(
    sourceTool: adapter.id,
    path: file.path,
    fileSize: Int(batch.fileSize),
    modifiedAt: batch.modifiedAt,
    fileId: checkpoint?.fileId,
    readOffset: Int(batch.nextOffset),
    parseContext: context,
    importedEventCount: events.count,
    status: "ok",
    lastError: nil
))
```

## 5. Codex 当前规则

Codex 是主要的 context 需求方：

- `session_meta` 提供 session/cwd/provider。
- `turn_context` 提供或更新 model/provider/cwd。
- `token_count` 行可能只包含 usage，需要从 context fallback model/provider/session。
- `bootstrapContext` 可在已有 offset 但无 context 时，从文件开头扫描到 checkpoint 位置以重建上下文。

当前测试覆盖：

- `test_parseLines_usesPersistedContextWhenBatchHasOnlyTokenCount`
- `test_bootstrapContext_scansPriorContextBeforeCheckpoint`

## 6. 隐私约束

parse context 只允许保存：

- session id
- cwd
- provider id
- model

禁止保存：

- prompt / user message
- response / assistant text
- tool output
- thinking 原文
- Authorization / API key
- raw JSON line

相关测试：`PrivacyLocalWatcherTests`。

## 7. 完成标准

已满足：

- Codex 不需要在 watcher 常规路径中全文件解析。
- append 后只读取新增完整行。
- App 重启后能从 `read_offset + parse_context_json` 继续。
- token_count 单独到达时可从 context 拿到 model/provider/session/cwd。
- `swift test` 全绿。