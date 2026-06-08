import Foundation
import GRDB

public struct ImportResult: Equatable {
    public let inserted: Int
    public let skipped: Int
    public let failed: Int
    /// Total input tokens of newly inserted events (excludes skipped duplicates).
    public let inputTokens: Int
    /// Total output tokens of newly inserted events (excludes skipped duplicates).
    public let outputTokens: Int

    public init(inserted: Int, skipped: Int, failed: Int, inputTokens: Int = 0, outputTokens: Int = 0) {
        self.inserted = inserted
        self.skipped = skipped
        self.failed = failed
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct LocalScanSourceStatus {
    public let sourceTool: String
    public let displayName: String
    public let rootPath: String
    public let status: String
    public let lastScanStartedAt: Date?
    public let lastScanFinishedAt: Date?
    public let filesSeen: Int
    public let filesScanned: Int
    public let eventsImported: Int
    public let parseErrorCount: Int
    public let lastError: String?

    public init(sourceTool: String, displayName: String, rootPath: String, status: String, lastScanStartedAt: Date?, lastScanFinishedAt: Date?, filesSeen: Int, filesScanned: Int, eventsImported: Int, parseErrorCount: Int, lastError: String?) {
        self.sourceTool = sourceTool
        self.displayName = displayName
        self.rootPath = rootPath
        self.status = status
        self.lastScanStartedAt = lastScanStartedAt
        self.lastScanFinishedAt = lastScanFinishedAt
        self.filesSeen = filesSeen
        self.filesScanned = filesScanned
        self.eventsImported = eventsImported
        self.parseErrorCount = parseErrorCount
        self.lastError = lastError
    }
}

public struct LocalScanSource: Identifiable, Equatable {
    public var id: String { sourceTool }
    public let sourceTool: String
    public let displayName: String
    public let rootPath: String
    public let status: String
    public let lastScanStartedAt: Date?
    public let lastScanFinishedAt: Date?
    public let filesSeen: Int
    public let filesScanned: Int
    public let eventsImported: Int
    public let parseErrorCount: Int
    public let lastError: String?
}

public struct LocalScanFileStatus {
    public let sourceTool: String
    public let path: String
    public let fileSize: Int
    public let modifiedAt: Date?
    public let lastScannedAt: Date?
    public let importedEventCount: Int
    public let status: String
    public let lastError: String?

    public init(sourceTool: String, path: String, fileSize: Int, modifiedAt: Date?, lastScannedAt: Date?, importedEventCount: Int, status: String, lastError: String?) {
        self.sourceTool = sourceTool
        self.path = path
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.lastScannedAt = lastScannedAt
        self.importedEventCount = importedEventCount
        self.status = status
        self.lastError = lastError
    }
}

public final class LocalScanRepository {
    private struct PreparedUsageEvent {
        let event: LocalUsageEvent
        let providerId: String
        let costUsd: Double
    }

    private let dbManager: DatabaseManager
    private let costCalculator: CostCalculator

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
        self.costCalculator = CostCalculator(pricingRepo: ModelsRepository(dbManager: dbManager))
    }

    public func upsertSourceStatus(_ status: LocalScanSourceStatus) throws {
        let now = ISO8601DateCoding.string(from: Date())
        try dbManager.writer.write { db in
            try db.execute(sql: """
                INSERT INTO local_scan_sources
                (source_tool, display_name, root_path, status, last_scan_started_at, last_scan_finished_at,
                 files_seen, files_scanned, events_imported, parse_error_count, last_error, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_tool) DO UPDATE SET
                  display_name = excluded.display_name,
                  root_path = excluded.root_path,
                  status = excluded.status,
                  last_scan_started_at = excluded.last_scan_started_at,
                  last_scan_finished_at = excluded.last_scan_finished_at,
                  files_seen = excluded.files_seen,
                  files_scanned = excluded.files_scanned,
                  events_imported = excluded.events_imported,
                  parse_error_count = excluded.parse_error_count,
                  last_error = excluded.last_error,
                  updated_at = excluded.updated_at
                """, arguments: [
                    status.sourceTool, status.displayName, status.rootPath, status.status,
                    status.lastScanStartedAt.map(ISO8601DateCoding.string(from:)),
                    status.lastScanFinishedAt.map(ISO8601DateCoding.string(from:)),
                    status.filesSeen, status.filesScanned, status.eventsImported,
                    status.parseErrorCount, status.lastError, now
                ])
        }
    }

    public func upsertFileStatus(_ status: LocalScanFileStatus) throws {
        try dbManager.writer.write { db in
            try db.execute(sql: """
                INSERT INTO local_scan_files
                (id, source_tool, path, file_size, modified_at, last_scanned_at, imported_event_count, status, last_error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_tool, path) DO UPDATE SET
                  file_size = excluded.file_size,
                  modified_at = excluded.modified_at,
                  last_scanned_at = excluded.last_scanned_at,
                  imported_event_count = excluded.imported_event_count,
                  status = excluded.status,
                  last_error = excluded.last_error
                """, arguments: [
                    "\(status.sourceTool)::\(status.path)", status.sourceTool, status.path,
                    status.fileSize, status.modifiedAt.map(ISO8601DateCoding.string(from:)),
                    status.lastScannedAt.map(ISO8601DateCoding.string(from:)), status.importedEventCount,
                    status.status, status.lastError
                ])
        }
    }

    // MARK: - Checkpoint

    /// Retrieve the checkpoint for a file so incremental reading knows where to resume.
    public func checkpoint(for sourceTool: String, path: String) throws -> LocalScanFileCheckpoint? {
        try dbManager.reader.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT file_size, modified_at, file_id, read_offset, parse_context_json, last_scanned_at
                FROM local_scan_files
                WHERE source_tool = ? AND path = ?
                """, arguments: [sourceTool, path]) else { return nil }
            let contextJSON = row["parse_context_json"] as String?
            return LocalScanFileCheckpoint(
                sourceTool: sourceTool,
                path: path,
                fileSize: row["file_size"],
                modifiedAt: (row["modified_at"] as String?).flatMap(ISO8601DateCoding.parse),
                fileId: row["file_id"],
                readOffset: row["read_offset"],
                lastScannedAt: (row["last_scanned_at"] as String?).flatMap(ISO8601DateCoding.parse),
                parseContext: contextJSON.map { LocalUsageParseContext(sourceTool: sourceTool, json: $0) }
            )
        }
    }

    public func fetchSources() throws -> [LocalScanSource] {
        try dbManager.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM local_scan_sources ORDER BY source_tool").map { row in
                LocalScanSource(
                    sourceTool: row["source_tool"],
                    displayName: row["display_name"],
                    rootPath: row["root_path"],
                    status: row["status"],
                    lastScanStartedAt: ISO8601DateCoding.parse((row["last_scan_started_at"] as String?) ?? ""),
                    lastScanFinishedAt: ISO8601DateCoding.parse((row["last_scan_finished_at"] as String?) ?? ""),
                    filesSeen: row["files_seen"],
                    filesScanned: row["files_scanned"],
                    eventsImported: row["events_imported"],
                    parseErrorCount: row["parse_error_count"],
                    lastError: row["last_error"]
                )
            }
        }
    }

    public func shouldScanFile(sourceTool: String, url: URL) throws -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let currentSize = (attrs?[.size] as? NSNumber)?.intValue
        return try dbManager.reader.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT file_size, status FROM local_scan_files WHERE source_tool = ? AND path = ?",
                arguments: [sourceTool, url.path]
            ) else { return true }
            guard row["status"] as String == "ok" else { return true }
            guard let currentSize else { return false }
            let storedSize: Int = row["file_size"]
            // JSONL files are append-only: file_size is the reliable change signal.
            // Don't compare modifiedAt — ISO8601 round-trip loses nanosecond precision.
            return storedSize != currentSize
        }
    }

    public func importUsageEvents(_ events: [LocalUsageEvent]) throws -> ImportResult {
        guard !events.isEmpty else {
            return ImportResult(inserted: 0, skipped: 0, failed: 0, inputTokens: 0, outputTokens: 0)
        }

        var inserted = 0
        var skipped = 0
        var totalInputTokens = 0
        var totalOutputTokens = 0
        let importedAt = ISO8601DateCoding.string(from: Date())
        let preparedEvents = try events.map(prepareUsageEvent)

        try dbManager.writer.write { db in
            for prepared in preparedEvents {
                let event = prepared.event
                let tokenUsageId = UUID().uuidString

                // Try insert into dedup table first
                do {
                    try db.execute(sql: """
                        INSERT INTO local_usage_imports
                        (key, source_tool, source_file, token_usage_id, imported_at)
                        VALUES (?, ?, ?, ?, ?)
                        """, arguments: [event.key, event.sourceTool, event.sourceFile, tokenUsageId, importedAt])
                } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                    skipped += 1
                    continue
                }

                // Only insert token_usage if dedup insert succeeded
                try db.execute(sql: """
                    INSERT INTO token_usages
                    (id, agentic_tool, provider_id, model,
                     input_tokens, output_tokens, cached_input_tokens, cache_write_tokens,
                     reasoning_tokens, total_tokens, cost_usd, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        tokenUsageId, event.sourceTool, prepared.providerId, event.model,
                        event.inputTokens, event.outputTokens, event.cacheReadTokens, event.cacheWriteTokens,
                        event.reasoningTokens, event.totalTokens, prepared.costUsd,
                        ISO8601DateCoding.string(from: event.timestamp)
                    ])
                inserted += 1
                totalInputTokens += event.inputTokens
                totalOutputTokens += event.outputTokens
            }
        }

        return ImportResult(inserted: inserted, skipped: skipped, failed: 0, inputTokens: totalInputTokens, outputTokens: totalOutputTokens)
    }

    /// Import a batch of usage events with key-based dedup, updating the file checkpoint atomically.
    public func importIncrementalUsageEvents(
        _ events: [LocalUsageEvent],
        checkpoint: LocalScanFileCheckpointUpdate
    ) throws -> ImportResult {
        guard !events.isEmpty else {
            // Still update the checkpoint even if no events
            try updateCheckpoint(checkpoint, importedEventCount: 0)
            return ImportResult(inserted: 0, skipped: 0, failed: 0, inputTokens: 0, outputTokens: 0)
        }

        var inserted = 0
        var skipped = 0
        var totalInputTokens = 0
        var totalOutputTokens = 0
        let importedAt = ISO8601DateCoding.string(from: Date())
        let preparedEvents = try events.map(prepareUsageEvent)

        try dbManager.writer.write { db in
            for prepared in preparedEvents {
                let event = prepared.event
                let tokenUsageId = UUID().uuidString
                do {
                    try db.execute(sql: """
                        INSERT INTO local_usage_imports
                        (key, source_tool, source_file, token_usage_id, imported_at)
                        VALUES (?, ?, ?, ?, ?)
                        """, arguments: [event.key, event.sourceTool, event.sourceFile, tokenUsageId, importedAt])
                } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                    skipped += 1
                    continue
                }

                try db.execute(sql: """
                    INSERT INTO token_usages
                    (id, agentic_tool, provider_id, model,
                     input_tokens, output_tokens, cached_input_tokens, cache_write_tokens,
                     reasoning_tokens, total_tokens, cost_usd, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        tokenUsageId, event.sourceTool, prepared.providerId, event.model,
                        event.inputTokens, event.outputTokens, event.cacheReadTokens, event.cacheWriteTokens,
                        event.reasoningTokens, event.totalTokens, prepared.costUsd,
                        ISO8601DateCoding.string(from: event.timestamp)
                    ])
                inserted += 1
                totalInputTokens += event.inputTokens
                totalOutputTokens += event.outputTokens
            }

            // Update checkpoint in the same transaction
            try updateCheckpointInDB(db, checkpoint: checkpoint, importedEventCount: inserted)
        }

        return ImportResult(inserted: inserted, skipped: skipped, failed: 0, inputTokens: totalInputTokens, outputTokens: totalOutputTokens)
    }

    private func updateCheckpoint(_ checkpoint: LocalScanFileCheckpointUpdate, importedEventCount: Int) throws {
        try dbManager.writer.write { db in
            try updateCheckpointInDB(db, checkpoint: checkpoint, importedEventCount: importedEventCount)
        }
    }

    private func prepareUsageEvent(_ event: LocalUsageEvent) throws -> PreparedUsageEvent {
        let providerId = event.providerId ?? fallbackProvider(for: event.sourceTool)
        let costUsd = try resolvedCost(for: event, providerId: providerId)
        return PreparedUsageEvent(event: event, providerId: providerId, costUsd: costUsd)
    }

    private func resolvedCost(for event: LocalUsageEvent, providerId: String) throws -> Double {
        if let costUsd = event.costUsd {
            return costUsd
        }

        guard let model = event.model else {
            return 0
        }

        let result = try costCalculator.calculate(CostInput(
            providerId: providerId,
            model: model,
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens,
            cachedInputTokens: event.cacheReadTokens,
            reasoningTokens: event.reasoningTokens,
            createdAt: event.timestamp
        ))
        return result.costUsd
    }

    private func updateCheckpointInDB(_ db: Database, checkpoint: LocalScanFileCheckpointUpdate, importedEventCount: Int) throws {
        let now = ISO8601DateCoding.string(from: Date())
        let fileId = "\(checkpoint.sourceTool)::\(checkpoint.path)"
        try db.execute(sql: """
            INSERT INTO local_scan_files
            (id, source_tool, path, file_size, modified_at, file_id, read_offset, parse_context_json,
             last_scanned_at, imported_event_count, status, last_error)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_tool, path) DO UPDATE SET
              file_size = excluded.file_size,
              modified_at = excluded.modified_at,
              file_id = excluded.file_id,
              read_offset = excluded.read_offset,
              parse_context_json = excluded.parse_context_json,
              last_scanned_at = excluded.last_scanned_at,
              imported_event_count = imported_event_count + excluded.imported_event_count,
              status = excluded.status,
              last_error = excluded.last_error
            """, arguments: [
                fileId, checkpoint.sourceTool, checkpoint.path,
                checkpoint.fileSize, checkpoint.modifiedAt.map(ISO8601DateCoding.string(from:)),
                checkpoint.fileId, checkpoint.readOffset, checkpoint.parseContext?.json,
                now, importedEventCount, checkpoint.status, checkpoint.lastError
            ])
    }

    private func fallbackProvider(for sourceTool: String) -> String {
        switch sourceTool {
        case "claude_code": return "anthropic"
        case "codex": return "openai"
        case "pi": return "anthropic"
        default: return sourceTool
        }
    }
}
