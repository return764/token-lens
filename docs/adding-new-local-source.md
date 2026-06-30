# Adding a New Local Source — Developer Guide

> 适用版本：TokenLens MVP (Local Record Scanner)  
> 最后更新：2026-06-30

本文档指导开发者如何为 TokenLens 添加一个新的本地源（Local Source），使 App 能够自动扫描并导入该工具写入的本地 usage 记录。记录可以是 append-only JSONL，也可以是 SQLite database 等其他本地存储。

---

## 1. 概念速览

TokenLens 通过 **LocalUsageAdapter** 协议接入不同的本地 agent 工具。每个 adapter 负责：

| 职责 | 方法 |
|------|------|
| 告诉扫描器有哪些逻辑记录 | `discoverRecords()` |
| 将文件系统事件归一成逻辑记录 | `candidates(fromChangedPaths:)` |
| 从逻辑记录读取 usage 增量 | `readUsageChanges(record:checkpoint:)` |

已有的 adapter 参考实现：

- `ClaudeCodeLocalUsageAdapter` — 扫描 `~/.claude/projects/**/*.jsonl`
- `CodexLocalUsageAdapter` — 扫描 `~/.codex/sessions/**/*.jsonl`
- `PiLocalUsageAdapter` — 扫描 `~/.pi/agent/sessions/**/*.jsonl`
- `OpenCodeLocalUsageAdapter` — 扫描 `~/.local/share/opencode/opencode.db`

---

## 2. 核心接口：`LocalUsageAdapter`

定义在 `Sources/TokenLensApp/Core/LocalRecords/LocalUsageModels.swift`：

```swift
public protocol LocalUsageAdapter {
    /// 唯一标识符，最终写入 token_usages.agentic_tool 字段。例如 "opencode"。
    var id: String { get }

    /// UI 中展示的名称。例如 "OpenCode"。
    var displayName: String { get }

    /// 本地记录 root。JSONL source 通常是目录，SQLite source 通常是数据库所在目录。
    var defaultRoot: URL { get }

    /// 发现 root 下所有需要扫描的逻辑记录。
    func discoverRecords() throws -> [LocalUsageRecord]

    /// 将 FSEvents changed paths 归一成需要读取的逻辑记录。
    func candidates(fromChangedPaths paths: [URL]) throws -> [LocalUsageRecord]

    /// 读取一个逻辑记录的 usage 增量并返回 checkpoint 更新。
    func readUsageChanges(
        record: LocalUsageRecord,
        checkpoint: LocalScanFileCheckpoint?
    ) throws -> LocalUsageSessionReadResult
}
```

`LocalUsageRecord` 描述真正读取的路径和稳定 checkpoint 路径：

```swift
public struct LocalUsageRecord: Equatable, Hashable {
    public let readURL: URL
    public let checkpointURL: URL
    public let displayPath: String
    public let kind: LocalUsageRecordKind
}
```

JSONL source 通常使用 `LocalUsageRecord.appendOnlyJSONL(file)`，`readURL` 和 `checkpointURL` 相同。SQLite source 可以把 WAL/SHM 变化归一到主 DB record，让 checkpoint 始终落在主 DB 路径。

### 2.1 返回的 `LocalUsageEvent`

```swift
public struct LocalUsageEvent: Equatable {
    public let key: String             // 去重 key，通过 LocalUsageKeyBuilder.build() 生成
    public let sourceTool: String      // adapter id
    public let sourceFile: String      // 逻辑记录的读取路径
    public let sourceEventId: String   // 源事件 ID（如 JSONL 中的 id 字段，或行号）
    public let sourceSessionId: String? // 会话 ID
    public let sourceCwd: String?      // 工作目录
    public let timestamp: Date         // 事件时间
    public let providerId: String?     // LLM provider（如 "openai", "anthropic"）
    public let model: String?          // 模型名
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int    // 缓存读取 token 数
    public let cacheWriteTokens: Int   // 缓存写入 token 数
    public let reasoningTokens: Int    // 推理 token 数
    public let totalTokens: Int
    public let costUsd: Double?       // 源已给出的 cost（可为 nil，由 CostCalculator 补充）
}
```

**⚠️ 关键：去重 key**

每个 `LocalUsageEvent` 必须使用 `LocalUsageKeyBuilder.build()` 生成唯一的去重 key。如果源记录中有稳定的 event id，用它作为 native id；否则系统会用 token 指纹做 hash 去重。

```swift
let key = LocalUsageKeyBuilder.build(
    sourceTool: id,
    nativeId: eventIdFromJSONL,   // 稳定 ID 或 nil
    timestamp: timestamp,
    providerId: providerId,
    model: model,
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: cacheRead,
    cacheWriteTokens: cacheWrite,
    reasoningTokens: reasoning,
    totalTokens: total,
    costUsd: cost
)
```

> 去重 key 的前缀格式：`<sourceTool>:native:<id>` 或 `<sourceTool>:usage:<sha256>`  
> 导入时会插入 `local_usage_imports` 表，UNIQUE 约束自动跳过重复事件。

---

## 3. 实现步骤（7 步）

### Step 1：理解目标记录格式

首先需要理解你要接入的工具的本地记录格式。JSONL source 需要知道：

- 每一行 JSON 的结构（通常按 `type` 字段区分事件类型）
- token usage 数据在哪个字段下
- 哪些字段跨行共享（session_id、cwd、model、provider 等）
- 哪些行需要提取，哪些可以跳过

> 💡 常见模式：session 信息出现在 JSONL 开头，后续的 event 行不重复携带 session 信息。此时通过 `AppendOnlyJSONLUsageReader` 的 `initialContext` 和 `parseContext` 来保留跨行状态。SQLite source 通常保存 aggregate watermark 到 `parse_context_json`。

### Step 2：创建 Adapter 文件

在 `Sources/TokenLensApp/Core/LocalRecords/` 下创建新的 Swift 文件。

**文件命名**：`<ToolName>LocalUsageAdapter.swift`

**最小 JSONL 模板**（无跨行上下文）：

```swift
import Foundation

public struct MyToolLocalUsageAdapter: LocalUsageAdapter, AppendOnlyJSONLUsageDecoding {
    public let defaultRoot: URL

    public var id: String { "mytool" }
    public var displayName: String { "MyTool" }

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".mytool/sessions")) {
        self.defaultRoot = root
    }

    public func discoverRecords() throws -> [LocalUsageRecord] {
        try LocalRecordJSON.discoverJSONLRecords(root: defaultRoot)
    }

    public func candidates(fromChangedPaths paths: [URL]) throws -> [LocalUsageRecord] {
        try LocalRecordJSON.candidateJSONLRecords(for: paths)
    }

    public func readUsageChanges(
        record: LocalUsageRecord,
        checkpoint: LocalScanFileCheckpoint?
    ) throws -> LocalUsageSessionReadResult {
        try AppendOnlyJSONLUsageReader()
            .readChanges(record: record, checkpoint: checkpoint, decoder: self)
    }

    public func parseJSONLLines(
        _ lines: [(lineNumber: Int?, text: String)],
        record: LocalUsageRecord,
        context: inout LocalUsageParseContext?
    ) throws -> [LocalUsageEvent] {
        var events: [LocalUsageEvent] = []

        for (lineNumber, line) in lines {
            guard let object = try LocalRecordJSON.object(from: line,
                    lineNumber: lineNumber ?? 0),
                  let event = usageEvent(from: object,
                    lineNumber: lineNumber ?? 0, file: record.readURL)
            else { continue }
            events.append(event)
        }

        return events
    }

    private func usageEvent(
        from object: [String: Any],
        lineNumber: Int,
        file: URL
    ) -> LocalUsageEvent? {
        // 1. 判断是否是需要提取的事件类型
        guard LocalRecordJSON.string(object, "type") == "usage",
              let usage = object["token_usage"] as? [String: Any]
        else { return nil }

        // 2. 提取字段
        let input    = LocalRecordJSON.int(usage, "input_tokens")
        let output   = LocalRecordJSON.int(usage, "output_tokens")
        let total    = LocalRecordJSON.int(usage, "total_tokens")
        let model    = LocalRecordJSON.string(object, "model")
        let provider = LocalRecordJSON.string(object, "provider") ?? "openai"
        let nativeId = LocalRecordJSON.string(object, "id")
        let timestamp = LocalRecordJSON.date(object, keys: ["timestamp", "created_at"])

        // 3. 生成去重 key
        let key = LocalUsageKeyBuilder.build(
            sourceTool: id,
            nativeId: nativeId,
            timestamp: timestamp,
            providerId: provider,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            costUsd: nil
        )

        // 4. 返回事件
        return LocalUsageEvent(
            key: key,
            sourceTool: id,
            sourceFile: file.path,
            sourceEventId: nativeId ?? "line-\(lineNumber)",
            sourceSessionId: nil,
            sourceCwd: nil,
            timestamp: timestamp,
            providerId: provider,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            reasoningTokens: 0,
            totalTokens: total,
            costUsd: nil
        )
    }
}
```

### Step 3（如需跨行上下文）：实现 Context 支持

如果 JSONL 中的 session_id、cwd、provider、model 等字段在前面的行（如 `session_meta` 事件）中定义，后续的 `token_count` 事件不重复携带，则你需要：

#### 3a. 定义 Context Payload

```swift
private struct MyToolParseContextPayload: Codable, Equatable {
    var sessionId: String?
    var cwd: String?
    var providerId: String? = "openai"
    var lastModel: String?

    mutating func ingest(_ object: [String: Any]) {
        let type = LocalRecordJSON.string(object, "type")
        switch type {
        case "session_start":
            sessionId = LocalRecordJSON.string(object, "id") ?? sessionId
            cwd = LocalRecordJSON.string(object, "cwd") ?? cwd
        case "model_use":
            lastModel = LocalRecordJSON.string(object, "model") ?? lastModel
            providerId = LocalRecordJSON.string(object, "provider") ?? providerId
        default:
            break
        }
    }
}
```

#### 3b. 实现 encode/decode

```swift
private func decodeContext(_ context: LocalUsageParseContext?) -> MyToolParseContextPayload? {
    guard let context, context.sourceTool == id,
          let data = context.json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(MyToolParseContextPayload.self, from: data)
}

private func makeContext(_ payload: MyToolParseContextPayload) -> LocalUsageParseContext? {
    guard let data = try? JSONEncoder().encode(payload),
          let json = String(data: data, encoding: .utf8) else { return nil }
    return LocalUsageParseContext(sourceTool: id, json: json)
}
```

#### 3c. 在 `parseJSONLLines` 中使用 context

```swift
public func parseJSONLLines(...) throws -> [LocalUsageEvent] {
    var payload = decodeContext(context) ?? MyToolParseContextPayload()
    var events: [LocalUsageEvent] = []

    for (lineNumber, line) in lines {
        guard let object = try LocalRecordJSON.object(from: line, ...) else { continue }
        payload.ingest(object)   // ← 先喂给 context
        if let event = usageEvent(from: object, ctx: payload) {
            events.append(event)
        }
    }

    context = makeContext(payload)  // ← 持久化 context
    return events
}
```

#### 3d. 可选：实现 `initialContext`

如果需要从文件中已有数据重建上下文：

```swift
public func initialContext(
    record: LocalUsageRecord,
    checkpoint: LocalScanFileCheckpoint?
) throws -> LocalUsageParseContext? {
    // 有缓存直接用
    if let context = checkpoint?.parseContext, context.sourceTool == id {
        return context
    }
    // 否则从文件头开始扫描重建
    guard let checkpoint, checkpoint.readOffset > 0 else { return nil }
    // ... 读取、解析、重建 payload
    return makeContext(payload)
}
```

> 📖 参考：`CodexLocalUsageAdapter` 是一个完整的跨行上下文实现。

---

### Step 4：注册 Adapter

编辑 `Sources/TokenLensApp/Core/LocalRecords/LocalUsageScanner.swift`。`LocalSourcesBackgroundService` 默认也使用这里的 adapter 列表，因此注册后启动扫描、后台监听、Rescan Now 都会自动包含新 source。

```swift
public static func defaultAdapters() -> [any LocalUsageAdapter] {
    [
        CodexLocalUsageAdapter(),
        ClaudeCodeLocalUsageAdapter(),
        PiLocalUsageAdapter(),
        OpenCodeLocalUsageAdapter(),
        MyToolLocalUsageAdapter(),  // ← 添加这一行
    ]
}
```

---

### Step 5：设置 Fallback Provider

编辑 `Sources/TokenLensApp/Database/LocalScanRepository.swift`：

```swift
private func fallbackProvider(for sourceTool: String) -> String {
    switch sourceTool {
    case "claude_code": return "anthropic"
    case "codex":       return "openai"
    case "pi":          return "anthropic"
    case "mytool":      return "openai"   // ← 添加
    default:            return sourceTool
    }
}
```

> 这个回退在 `LocalUsageEvent.providerId` 为 nil 时使用，用于确定 `token_usages.provider_id`，并在 `costUsd == nil` 时配合 `CostCalculator` 查询 `models` 表中的价格。

---

### Step 6：添加 UI 显示名

编辑 `Sources/TokenLensApp/Settings/SettingsTab.swift`：

```swift
private func localSourceDisplayName(_ sourceTool: String) -> String {
    switch sourceTool {
    case "claude_code": return "Claude Code"
    case "codex":       return "Codex"
    case "pi":          return "pi"
    case "mytool":      return "MyTool"   // ← 添加
    default:            return sourceTool
    }
}
```

---

### Step 7：编写测试

在 `Tests/TokenLensTests/` 下创建 `<ToolName>LocalUsageAdapterTests.swift`。

**必须覆盖的测试场景：**

| 测试方法 | 目标 |
|---------|------|
| `test_readUsageChanges_importsUsageEvents` | 读取正常 record → 返回正确事件 |
| `test_parseJSONLLines_extractsFromIncrementalLines` | JSONL 增量解析 → 正确处理单行/多行 |
| `test_parseJSONLLines_usesPersistedContext` | 给出已有 context 的前提下解析 → model/provider/session 正确（如有跨行上下文） |
| `test_initialContext_rebuildsContext` | 从已有行的 offset 重建上下文（如有跨行上下文） |
| `test_readUsageChanges_skipsIrrelevantLines` | 跳过不相关的事件类型 |
| `test_keyDeduplication` | 相同事件生成相同 key，不同事件生成不同 key |

**测试模板：**

```swift
import XCTest
@testable import TokenLensApp

final class MyToolLocalUsageAdapterTests: XCTestCase {
    func test_readUsageChanges_importsUsageEvents() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("mytool.jsonl")
        try writeJSONL([
            #"{"type":"usage","model":"gpt-4","provider":"openai","timestamp":"2026-06-12T10:00:00Z","id":"evt-1","token_usage":{"input_tokens":100,"output_tokens":50,"total_tokens":150}}"#,
        ], to: file)

        let adapter = MyToolLocalUsageAdapter(root: root)
        let events = try adapter
            .readUsageChanges(record: .appendOnlyJSONL(file), checkpoint: nil)
            .events

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.sourceTool, "mytool")
        XCTAssertEqual(event.providerId, "openai")
        XCTAssertEqual(event.model, "gpt-4")
        XCTAssertEqual(event.inputTokens, 100)
        XCTAssertEqual(event.outputTokens, 50)
        XCTAssertEqual(event.totalTokens, 150)
        XCTAssertTrue(event.key.hasPrefix("mytool:native:evt-1"))
    }

    // ... 其他测试

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenLensTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJSONL(_ lines: [String], to url: URL) throws {
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
```

运行测试：

```bash
swift test --filter MyToolLocalUsageAdapterTests
```

---

## 4. 常用工具方法

`LocalRecordJSON` 提供了一系列安全的数据提取方法（定义在 `LocalUsageModels.swift`）：

```swift
// 从一行 JSONL 文本解析为 dict
LocalRecordJSON.object(from: line, lineNumber: 3) -> [String: Any]?

// 安全提取字段
LocalRecordJSON.string(dict, "key")   -> String?
LocalRecordJSON.int(dict, "key")      -> Int        // 容错：String → Int
LocalRecordJSON.double(dict, "key")   -> Double?    // 容错：Int → Double

// 多 key fallback 时间解析
LocalRecordJSON.date(dict, keys: ["timestamp", "created_at", "createdAt"]) -> Date

// 发现 JSONL 文件
LocalRecordJSON.discoverJSONLFiles(root: url) -> [URL]
```

---

## 5. 文件变更清单（Checklist）

| # | 操作 | 文件 |
|---|------|------|
| 1 | **新建** | `Sources/TokenLensApp/Core/LocalRecords/<ToolName>LocalUsageAdapter.swift` |
| 2 | **修改** | `Sources/TokenLensApp/Core/LocalRecords/LocalUsageScanner.swift` — `defaultAdapters()` |
| 3 | **修改** | `Sources/TokenLensApp/Database/LocalScanRepository.swift` — `fallbackProvider(for:)` |
| 4 | **修改** | `Sources/TokenLensApp/Settings/SettingsTab.swift` — `localSourceDisplayName()` |
| 5 | **新建** | `Tests/TokenLensTests/<ToolName>LocalUsageAdapterTests.swift` |

---

## 6. 验证流程

完成以上 5 个变更后：

```bash
# 1. 编译
swift build

# 2. 运行新 adapter 的单元测试
swift test --filter MyToolLocalUsageAdapterTests

# 3. 运行全部测试确保无回归
swift test

# 4. （可选）实际运行 App 验证
swift run
# → 在 Settings > Local Sources 中应能看到新 source
# → 后台 watcher 启动后，目标目录新增/追加 JSONL usage 应自动导入
# → 用量数据应出现在 Recent Usage 中
```

---

## 7. 常见问题

### Q: Adapter 需要处理哪些 token 字段？

A: 尽可能全量。TokenLens token_usages 表支持六个维度：

| 字段 | 含义 |
|------|------|
| `input_tokens` | 输入 token |
| `output_tokens` | 输出 token |
| `cached_input_tokens` | 从缓存读取的输入 token |
| `cache_write_tokens` | 写入缓存的 token |
| `reasoning_tokens` | 推理（thinking）token |
| `total_tokens` | 总计 |

如果源 JSONL 没有某个字段，填 0 即可。`total_tokens` 如果源未提供，建议手动求和。

### Q: `total_tokens` 为 0 但其他字段有值怎么办？

A: 在构建 `LocalUsageEvent` 前自行求和：

```swift
let total = sourceTotalTokens == 0
    ? input + output + cacheRead + cacheWrite + reasoning
    : sourceTotalTokens
```

### Q: 什么时候需要 `initialContext`？

A: 当 JSONL 中后面的事件行依赖前面行的信息时。典型场景：
- 第一行声明 `session_id` 和 `cwd`
- 中间行切换 `model`
- 最后一行只包含 usage，没有 model/provider 信息

如果每个 usage 行都自包含所有信息，则不需要实现 `initialContext`。

### Q: 如何确保去重正确？

A: 去重依赖 `local_usage_imports` 表的 UNIQUE(`key`) 约束。key 由 `LocalUsageKeyBuilder` 生成：
- 有稳定 native id → `mytool:native:evt-123`
- 无稳定 id → `mytool:usage:<sha256>`（用 token+time+provider+model 做指纹）

确保同一事件每次解析生成相同 key 即可。

### Q: `costUsd` 要填吗？

A: 如果源 JSONL 中包含 cost 信息，填上可避免后续重复计算。如果源没有，设为 `nil`，`LocalScanRepository` 会在导入时自动通过 `CostCalculator` 补算。

---

## 8. 参考实现

按复杂度排序，建议按以下顺序阅读：

| Adapter | 复杂度 | 特点 |
|---------|--------|------|
| `ClaudeCodeLocalUsageAdapter` | ⭐ 简单 | 无跨行上下文，每行自包含 |
| `PiLocalUsageAdapter` | ⭐⭐ 中等 | 轻量跨行上下文（session_id + cwd） |
| `CodexLocalUsageAdapter` | ⭐⭐⭐ 复杂 | 完整跨行上下文 + initialContext 文件回退重建 |
| `OpenCodeLocalUsageAdapter` | ⭐⭐⭐ 复杂 | SQLite aggregate delta + WAL/SHM 归一到主 DB checkpoint |
