import Foundation

public struct CodexLocalUsageAdapter: LocalUsageAdapter {
    public let defaultRoot: URL

    public var id: String { "codex" }
    public var displayName: String { "Codex" }

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) {
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

    public func bootstrapContext(file: URL, checkpoint: LocalScanFileCheckpoint?) throws -> LocalUsageParseContext? {
        if let context = checkpoint?.parseContext, context.sourceTool == id {
            return context
        }

        guard let checkpoint, checkpoint.readOffset > 0 else { return nil }
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let bytesToRead = min(Int64(checkpoint.readOffset), fileSize)
        guard bytesToRead > 0 else { return nil }

        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: Int(bytesToRead)),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var payload = CodexParseContextPayload()
        for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
            guard let object = try LocalRecordJSON.object(from: line, lineNumber: offset + 1) else { continue }
            payload.ingest(object)
        }
        return makeContext(payload)
    }

    public func parseLines(
        _ lines: [(lineNumber: Int?, text: String)],
        file: URL,
        context: inout LocalUsageParseContext?
    ) throws -> [LocalUsageEvent] {
        var payload = decodeContext(context) ?? CodexParseContextPayload()
        var events: [LocalUsageEvent] = []

        for (lineNumber, line) in lines {
            let effectiveLineNumber = lineNumber ?? 0
            guard let object = try LocalRecordJSON.object(from: line, lineNumber: effectiveLineNumber) else { continue }
            payload.ingest(object)
            if let event = try makeEvent(from: object, file: file, lineNumber: effectiveLineNumber, ctx: payload) {
                events.append(event)
            }
        }

        context = makeContext(payload)
        return events
    }

    // MARK: - Internal

    private func makeEvent(from object: [String: Any], file: URL, lineNumber: Int, ctx: CodexParseContextPayload) throws -> LocalUsageEvent? {
        guard LocalRecordJSON.string(object, "type") == "event_msg",
              let payload = object["payload"] as? [String: Any],
              LocalRecordJSON.string(payload, "type") == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any] else { return nil }

        let output = LocalRecordJSON.int(usage, "output_tokens")
        let cacheRead = LocalRecordJSON.int(usage, "cached_input_tokens")
        let reasoning = LocalRecordJSON.int(usage, "reasoning_output_tokens")
        // Codex's input_tokens includes cached tokens, so we subtract cacheRead.
        let input = max(LocalRecordJSON.int(usage, "input_tokens") - cacheRead, 0)
        let total = LocalRecordJSON.int(usage, "total_tokens") == 0
            ? input + output + cacheRead + reasoning
            : LocalRecordJSON.int(usage, "total_tokens")
        let timestamp = LocalRecordJSON.date(object, keys: ["timestamp", "created_at", "createdAt"])
        let eventId = "\(lineNumber)-\(LocalRecordJSON.string(object, "timestamp") ?? "")-\(stableUsageHash(usage))"

        let eventModel = LocalRecordJSON.string(payload, "model")
            ?? LocalRecordJSON.string(info, "model")
            ?? LocalRecordJSON.string(usage, "model")
            ?? ctx.lastModel

        let eventProvider = LocalRecordJSON.string(payload, "provider")
            ?? LocalRecordJSON.string(info, "provider")
            ?? ctx.providerId
            ?? "openai"

        let key = LocalUsageKeyBuilder.buildFromUsageDict(
            sourceTool: id,
            nativeId: LocalRecordJSON.string(object, "id"),
            timestamp: timestamp,
            providerId: eventProvider,
            model: eventModel,
            usage: usage
        )

        return LocalUsageEvent(
            key: key,
            sourceTool: id,
            sourceFile: file.path,
            sourceEventId: eventId,
            sourceSessionId: ctx.sessionId,
            sourceCwd: ctx.cwd,
            timestamp: timestamp,
            providerId: eventProvider,
            model: eventModel,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: 0,
            reasoningTokens: reasoning,
            totalTokens: total,
            costUsd: nil
        )
    }

    private func decodeContext(_ context: LocalUsageParseContext?) -> CodexParseContextPayload? {
        guard let context, context.sourceTool == id, let data = context.json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CodexParseContextPayload.self, from: data)
    }

    private func makeContext(_ payload: CodexParseContextPayload) -> LocalUsageParseContext? {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return LocalUsageParseContext(sourceTool: id, json: json)
    }

    private func stableUsageHash(_ usage: [String: Any]) -> String {
        let keys = usage.keys.sorted()
        let canonical = keys.map { "\($0)=\(usage[$0] ?? "")" }.joined(separator: "|")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

// MARK: - Parse context

private struct CodexParseContextPayload: Codable, Equatable {
    var sessionId: String?
    var cwd: String?
    var providerId: String? = "openai"
    var lastModel: String?

    mutating func ingest(_ object: [String: Any]) {
        let type = LocalRecordJSON.string(object, "type")

        switch type {
        case "session_meta":
            if let payload = object["payload"] as? [String: Any] {
                sessionId = sessionId
                    ?? LocalRecordJSON.string(payload, "id")
                    ?? LocalRecordJSON.string(payload, "session_id")
                    ?? LocalRecordJSON.string(payload, "sessionId")
                cwd = cwd ?? LocalRecordJSON.string(payload, "cwd")
                providerId = LocalRecordJSON.string(payload, "model_provider")
                    ?? LocalRecordJSON.string(payload, "provider")
                    ?? providerId
            }

        case "turn_context":
            if let payload = object["payload"] as? [String: Any] {
                lastModel = LocalRecordJSON.string(payload, "model") ?? lastModel
                cwd = LocalRecordJSON.string(payload, "cwd") ?? cwd
                providerId = LocalRecordJSON.string(payload, "model_provider")
                    ?? LocalRecordJSON.string(payload, "provider")
                    ?? providerId
            }

        default:
            break
        }
    }
}
