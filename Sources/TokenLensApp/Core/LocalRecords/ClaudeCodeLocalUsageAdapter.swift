import Foundation

public struct ClaudeCodeLocalUsageAdapter: LocalUsageAdapter {
    public let defaultRoot: URL

    public var id: String { "claude_code" }
    public var displayName: String { "Claude Code" }

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.defaultRoot = root
    }

    public func discoverFiles() throws -> [URL] {
        try LocalRecordJSON.discoverJSONLFiles(root: defaultRoot)
    }

    public func parseFile(_ url: URL) throws -> [LocalUsageEvent] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).enumerated().map { offset, line in
            (lineNumber: Optional(offset + 1), text: line)
        }
        var context: LocalUsageParseContext?
        return try parseLines(lines, file: url, context: &context)
    }

    public func parseLines(
        _ lines: [(lineNumber: Int?, text: String)],
        file: URL,
        context: inout LocalUsageParseContext?
    ) throws -> [LocalUsageEvent] {
        var events: [LocalUsageEvent] = []

        for (lineNumber, line) in lines {
            guard let object = try LocalRecordJSON.object(from: line, lineNumber: lineNumber ?? 0),
                  let event = usageEvent(from: object, lineNumber: lineNumber ?? 0, file: file) else { continue }
            events.append(event)
        }

        context = nil
        return events
    }

    private func usageEvent(from object: [String: Any], lineNumber: Int, file: URL) -> LocalUsageEvent? {
        let message = object["message"] as? [String: Any]
        let usage = (message?["usage"] as? [String: Any])
            ?? (object["usage"] as? [String: Any])
        guard let usage else { return nil }

        let role = LocalRecordJSON.string(message ?? object, "role")
        let type = LocalRecordJSON.string(object, "type")
        guard role == nil || role == "assistant" || type == "assistant" || type == "result" else { return nil }

        let input = LocalRecordJSON.int(usage, "input_tokens")
        let output = LocalRecordJSON.int(usage, "output_tokens")
        let cacheWrite = LocalRecordJSON.int(usage, "cache_creation_input_tokens")
        let cacheRead = LocalRecordJSON.int(usage, "cache_read_input_tokens")
        let reasoning = LocalRecordJSON.int(usage, "reasoning_tokens")
        let total = LocalRecordJSON.int(usage, "total_tokens") == 0
            ? input + output + cacheWrite + cacheRead + reasoning
            : LocalRecordJSON.int(usage, "total_tokens")
        let sessionId = LocalRecordJSON.string(object, "sessionId")
            ?? LocalRecordJSON.string(object, "session_id")
            ?? LocalRecordJSON.string(object, "uuid")
        let cwd = LocalRecordJSON.string(object, "cwd") ?? cwdFromClaudeProjectFile(file)
        let cost = LocalRecordJSON.double(object, "costUSD")
            ?? LocalRecordJSON.double(object, "cost_usd")
            ?? LocalRecordJSON.double(usage, "costUSD")
            ?? LocalRecordJSON.double(usage, "cost_usd")
        let timestamp = LocalRecordJSON.date(object, keys: ["timestamp", "created_at", "createdAt"])
        let model = LocalRecordJSON.string(message ?? [:], "model") ?? LocalRecordJSON.string(object, "model")

        let nativeId = LocalRecordJSON.string(object, "id")
            ?? LocalRecordJSON.string(object, "uuid")
        let key = LocalUsageKeyBuilder.build(
            sourceTool: id,
            nativeId: nativeId,
            timestamp: timestamp,
            providerId: "anthropic",
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            reasoningTokens: reasoning,
            totalTokens: total,
            costUsd: cost
        )

        return LocalUsageEvent(
            key: key,
            sourceTool: id,
            sourceFile: file.path,
            sourceEventId: nativeId ?? "line-\(lineNumber)",
            sourceSessionId: sessionId,
            sourceCwd: cwd,
            timestamp: timestamp,
            providerId: "anthropic",
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            reasoningTokens: reasoning,
            totalTokens: total,
            costUsd: cost
        )
    }

    private func cwdFromClaudeProjectFile(_ url: URL) -> String? {
        let directoryName = url.deletingLastPathComponent().lastPathComponent
        guard !directoryName.isEmpty else { return nil }
        return directoryName.replacingOccurrences(of: "-", with: "/")
    }
}
