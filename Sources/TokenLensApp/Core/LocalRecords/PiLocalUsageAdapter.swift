import Foundation

public struct PiLocalUsageAdapter: LocalUsageAdapter {
    public let defaultRoot: URL

    public var id: String { "pi" }
    public var displayName: String { "pi" }

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent/sessions")) {
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
        var payload = decodeContext(context) ?? PiParseContextPayload()
        var events: [LocalUsageEvent] = []

        for (lineNumber, line) in lines {
            guard let object = try LocalRecordJSON.object(from: line, lineNumber: lineNumber ?? 0) else { continue }
            let type = LocalRecordJSON.string(object, "type")

            if type == "session" {
                payload.sessionId = LocalRecordJSON.string(object, "id") ?? LocalRecordJSON.string(object, "sessionId") ?? payload.sessionId
                payload.cwd = LocalRecordJSON.string(object, "cwd") ?? payload.cwd
                continue
            }

            if let event = usageEvent(
                from: object,
                lineNumber: lineNumber ?? 0,
                sourceFile: file.path,
                sessionId: payload.sessionId,
                cwd: payload.cwd
            ) {
                events.append(event)
            }
        }

        context = makeContext(payload)
        return events
    }

    private func decodeContext(_ context: LocalUsageParseContext?) -> PiParseContextPayload? {
        guard let context, context.sourceTool == id, let data = context.json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PiParseContextPayload.self, from: data)
    }

    private func makeContext(_ payload: PiParseContextPayload) -> LocalUsageParseContext? {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return LocalUsageParseContext(sourceTool: id, json: json)
    }

    private func usageEvent(
        from object: [String: Any],
        lineNumber: Int,
        sourceFile: String,
        sessionId: String?,
        cwd: String?
    ) -> LocalUsageEvent? {
        guard LocalRecordJSON.string(object, "type") == "message",
              let message = object["message"] as? [String: Any],
              LocalRecordJSON.string(message, "role") == "assistant",
              let usage = message["usage"] as? [String: Any] else { return nil }

        let input = LocalRecordJSON.int(usage, "input")
        let output = LocalRecordJSON.int(usage, "output")
        let cacheRead = LocalRecordJSON.int(usage, "cacheRead")
        let cacheWrite = LocalRecordJSON.int(usage, "cacheWrite")
        let reasoning = LocalRecordJSON.int(usage, "reasoning")
        let total = LocalRecordJSON.int(usage, "totalTokens") == 0
            ? input + output + cacheRead + cacheWrite + reasoning
            : LocalRecordJSON.int(usage, "totalTokens")

        if total == 0,
           input == 0,
           output == 0,
           cacheRead == 0,
           cacheWrite == 0,
           reasoning == 0,
           LocalRecordJSON.string(message, "stopReason") == "error" {
            return nil
        }

        let cost = (usage["cost"] as? [String: Any]).flatMap { LocalRecordJSON.double($0, "total") }
            ?? LocalRecordJSON.double(usage, "costUsd")
            ?? LocalRecordJSON.double(usage, "cost_usd")

        let timestamp = LocalRecordJSON.date(object, keys: ["timestamp", "created_at", "createdAt"])
        let nativeId = LocalRecordJSON.string(object, "id")
        let providerId = LocalRecordJSON.string(message, "provider")
        let model = LocalRecordJSON.string(message, "model")
        let key = LocalUsageKeyBuilder.build(
            sourceTool: id,
            nativeId: nativeId,
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

        return LocalUsageEvent(
            key: key,
            sourceTool: id,
            sourceFile: sourceFile,
            sourceEventId: nativeId ?? "line-\(lineNumber)",
            sourceSessionId: sessionId,
            sourceCwd: cwd,
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
    }
}

private struct PiParseContextPayload: Codable, Equatable {
    var sessionId: String?
    var cwd: String?
}
