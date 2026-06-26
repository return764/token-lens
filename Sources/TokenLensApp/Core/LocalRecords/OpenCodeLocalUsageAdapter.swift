import Foundation
import GRDB

public struct OpenCodeLocalUsageAdapter: LocalUsageAdapter {
    public let defaultRoot: URL

    public var id: String { "opencode" }
    public var displayName: String { "OpenCode" }

    private var databaseURL: URL {
        defaultRoot.appendingPathComponent("opencode.db")
    }

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode")) {
        self.defaultRoot = root
    }

    public func discoverFiles() throws -> [URL] {
        FileManager.default.fileExists(atPath: databaseURL.path)
            ? [databaseURL.resolvingSymlinksInPath()]
            : []
    }

    public func candidates(fromChangedPaths paths: [URL]) throws -> [URL] {
        let canonicalDatabase = databaseURL.resolvingSymlinksInPath()
        var shouldScan = false

        for path in paths {
            let filename = path.lastPathComponent
            if path.path == defaultRoot.path || filename == "opencode.db" || filename == "opencode.db-wal" || filename == "opencode.db-shm" {
                shouldScan = true
                break
            }
        }

        return shouldScan && FileManager.default.fileExists(atPath: databaseURL.path)
            ? [canonicalDatabase]
            : []
    }

    public func parseFile(_ url: URL) throws -> [LocalUsageEvent] {
        let result = try readSessionChanges(file: url, checkpoint: nil)
        return result.events
    }

    public func parseLines(
        _ lines: [(lineNumber: Int?, text: String)],
        file: URL,
        context: inout LocalUsageParseContext?
    ) throws -> [LocalUsageEvent] {
        []
    }

    public func readSessionChanges(file: URL, checkpoint: LocalScanFileCheckpoint?) throws -> LocalUsageSessionReadResult {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let modifiedAt = attributes?[.modificationDate] as? Date

        var contextPayload = decodeContext(checkpoint?.parseContext) ?? OpenCodeParseContextPayload()
        let rows = try fetchSessionRows(from: file)
        var events: [LocalUsageEvent] = []

        for row in rows {
            let current = row.aggregate
            let previous = contextPayload.sessions[row.id]
            let delta = current.delta(from: previous)

            if delta.hasUsage {
                let modelInfo = parseModelInfo(row.modelJSON)
                let nativeId = "session:\(row.id):updated:\(row.timeUpdated):\(delta.fingerprint)"
                let timestamp = date(fromOpenCodeTimestamp: row.timeUpdated == 0 ? row.timeCreated : row.timeUpdated)
                let key = LocalUsageKeyBuilder.build(
                    sourceTool: id,
                    nativeId: nativeId,
                    timestamp: timestamp,
                    providerId: modelInfo.providerId,
                    model: modelInfo.model,
                    inputTokens: delta.input,
                    outputTokens: delta.output,
                    cacheReadTokens: delta.cacheRead,
                    cacheWriteTokens: delta.cacheWrite,
                    reasoningTokens: delta.reasoning,
                    totalTokens: delta.totalTokens,
                    costUsd: delta.costUsd
                )

                events.append(LocalUsageEvent(
                    key: key,
                    sourceTool: id,
                    sourceFile: file.path,
                    sourceEventId: nativeId,
                    sourceSessionId: row.id,
                    sourceCwd: row.directory,
                    timestamp: timestamp,
                    providerId: modelInfo.providerId,
                    model: modelInfo.model,
                    inputTokens: delta.input,
                    outputTokens: delta.output,
                    cacheReadTokens: delta.cacheRead,
                    cacheWriteTokens: delta.cacheWrite,
                    reasoningTokens: delta.reasoning,
                    totalTokens: delta.totalTokens,
                    costUsd: delta.costUsd
                ))
            }

            if current.hasUsage || previous != nil {
                contextPayload.sessions[row.id] = current
            }
        }

        let parseContext = makeContext(contextPayload)
        let checkpointUpdate = LocalScanFileCheckpointUpdate(
            sourceTool: id,
            path: file.path,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            fileId: checkpoint?.fileId,
            readOffset: fileSize,
            parseContext: parseContext,
            importedEventCount: events.count,
            status: "ok",
            lastError: nil
        )

        return LocalUsageSessionReadResult(
            events: events,
            checkpoint: checkpointUpdate,
            observedSize: fileSize,
            shouldReenqueue: false
        )
    }

    private func fetchSessionRows(from file: URL) throws -> [OpenCodeSessionRow] {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: file.path, configuration: configuration)

        return try queue.read { db in
            try validateSchema(db)
            return try Row.fetchAll(db, sql: """
                SELECT id, directory, model, cost,
                       tokens_input, tokens_output, tokens_reasoning,
                       tokens_cache_read, tokens_cache_write,
                       time_created, time_updated
                FROM session
                ORDER BY time_updated, id
                """).map(OpenCodeSessionRow.init(row:))
        }
    }

    private func validateSchema(_ db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(session)")
        let columns = Set(rows.compactMap { $0["name"] as String? })
        let required: Set<String> = [
            "id", "directory", "model", "cost",
            "tokens_input", "tokens_output", "tokens_reasoning",
            "tokens_cache_read", "tokens_cache_write",
            "time_created", "time_updated"
        ]
        let missing = required.subtracting(columns).sorted()
        guard missing.isEmpty else {
            throw LocalUsageParseError.unsupportedSourceSchema("Unsupported OpenCode session schema; missing columns: \(missing.joined(separator: ", "))")
        }
    }

    private func decodeContext(_ context: LocalUsageParseContext?) -> OpenCodeParseContextPayload? {
        guard let context, context.sourceTool == id, let data = context.json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OpenCodeParseContextPayload.self, from: data)
    }

    private func makeContext(_ payload: OpenCodeParseContextPayload) -> LocalUsageParseContext? {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return LocalUsageParseContext(sourceTool: id, json: json)
    }

    private func parseModelInfo(_ json: String?) -> (providerId: String?, model: String?) {
        guard let json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }

        let providerId = LocalRecordJSON.string(object, "providerID")
            ?? LocalRecordJSON.string(object, "providerId")
            ?? LocalRecordJSON.string(object, "provider")
        let model = LocalRecordJSON.string(object, "id")
            ?? LocalRecordJSON.string(object, "model")
            ?? LocalRecordJSON.string(object, "name")
        return (providerId, model)
    }

    private func date(fromOpenCodeTimestamp value: Int64) -> Date {
        if value > 10_000_000_000 {
            return Date(timeIntervalSince1970: Double(value) / 1000.0)
        }
        if value > 0 {
            return Date(timeIntervalSince1970: Double(value))
        }
        return Date()
    }
}

private struct OpenCodeSessionRow {
    let id: String
    let directory: String?
    let modelJSON: String?
    let timeCreated: Int64
    let timeUpdated: Int64
    let aggregate: OpenCodeSessionAggregate

    init(row: Row) {
        id = row["id"] as String
        directory = row["directory"] as String?
        modelJSON = row["model"] as String?
        timeCreated = (row["time_created"] as Int64?) ?? 0
        timeUpdated = (row["time_updated"] as Int64?) ?? 0
        aggregate = OpenCodeSessionAggregate(
            input: (row["tokens_input"] as Int?) ?? 0,
            output: (row["tokens_output"] as Int?) ?? 0,
            reasoning: (row["tokens_reasoning"] as Int?) ?? 0,
            cacheRead: (row["tokens_cache_read"] as Int?) ?? 0,
            cacheWrite: (row["tokens_cache_write"] as Int?) ?? 0,
            costUsd: (row["cost"] as Double?) ?? 0
        )
    }
}

private struct OpenCodeParseContextPayload: Codable, Equatable {
    var sessions: [String: OpenCodeSessionAggregate] = [:]
}

private struct OpenCodeSessionAggregate: Codable, Equatable {
    var input: Int
    var output: Int
    var reasoning: Int
    var cacheRead: Int
    var cacheWrite: Int
    var costUsd: Double

    var totalTokens: Int {
        input + output + reasoning + cacheRead + cacheWrite
    }

    var hasUsage: Bool {
        totalTokens > 0 || costUsd > 0
    }

    func delta(from previous: OpenCodeSessionAggregate?) -> OpenCodeSessionDelta {
        guard let previous else {
            return OpenCodeSessionDelta(
                input: input,
                output: output,
                reasoning: reasoning,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                costUsd: costUsd
            )
        }

        let reset = input < previous.input
            || output < previous.output
            || reasoning < previous.reasoning
            || cacheRead < previous.cacheRead
            || cacheWrite < previous.cacheWrite
            || costUsd < previous.costUsd

        if reset {
            return OpenCodeSessionDelta(
                input: input,
                output: output,
                reasoning: reasoning,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                costUsd: costUsd
            )
        }

        return OpenCodeSessionDelta(
            input: input - previous.input,
            output: output - previous.output,
            reasoning: reasoning - previous.reasoning,
            cacheRead: cacheRead - previous.cacheRead,
            cacheWrite: cacheWrite - previous.cacheWrite,
            costUsd: costUsd - previous.costUsd
        )
    }
}

private struct OpenCodeSessionDelta: Equatable {
    let input: Int
    let output: Int
    let reasoning: Int
    let cacheRead: Int
    let cacheWrite: Int
    let costUsd: Double

    var totalTokens: Int {
        input + output + reasoning + cacheRead + cacheWrite
    }

    var hasUsage: Bool {
        totalTokens > 0 || costUsd > 0
    }

    var fingerprint: String {
        [
            "in=\(input)",
            "out=\(output)",
            "reasoning=\(reasoning)",
            "cache_read=\(cacheRead)",
            "cache_write=\(cacheWrite)",
            "cost=\(String(format: "%.6f", costUsd))"
        ].joined(separator: "|")
    }
}
