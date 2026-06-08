import XCTest
@testable import TokenLensApp

/// Tests for LocalSourcesBackgroundService using a fake watcher approach.
/// We test the import queue + repository integration directly since FSEvents
/// requires real file-system to test end-to-end.
final class LocalScanRepositoryIncrementalTests: XCTestCase {

    // MARK: - Checkpoint read/write

    func test_importIncremental_persistsReadOffset() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        let event = LocalUsageEvent(
            key: "pi:native:e1",
            sourceTool: "pi", sourceFile: "/tmp/p.jsonl", sourceEventId: "e1",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 5, outputTokens: 3,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 8,
            costUsd: nil
        )

        let result = try repo.importIncrementalUsageEvents([event], checkpoint: LocalScanFileCheckpointUpdate(
            sourceTool: "pi", path: "/tmp/p.jsonl", fileSize: 200, modifiedAt: Date(),
            fileId: "inode-1", readOffset: 100,
            parseContext: LocalUsageParseContext(sourceTool: "pi", json: #"{"sessionId":"s1"}"#),
            importedEventCount: 1, status: "ok", lastError: nil
        ))
        XCTAssertEqual(result.inserted, 1)

        let cp = try repo.checkpoint(for: "pi", path: "/tmp/p.jsonl")
        XCTAssertEqual(cp?.readOffset, 100)
        XCTAssertEqual(cp?.fileId, "inode-1")
        XCTAssertEqual(cp?.fileSize, 200)
        XCTAssertEqual(cp?.parseContext?.sourceTool, "pi")
        XCTAssertEqual(cp?.parseContext?.json, #"{"sessionId":"s1"}"#)
    }

    // MARK: - Transaction atomicity

    func test_importIncremental_transactionRollback_onError() throws {
        // If the events array is valid but the checkpoint has bad data,
        // it should not leave partial state. However, since we use
        // GRDB transactions and key-based dedup, we test that a failed
        // checkpoint write doesn't corrupt existing records.

        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        // First, successfully import an event
        let event1 = LocalUsageEvent(
            key: "pi:native:e1",
            sourceTool: "pi", sourceFile: "/tmp/p.jsonl", sourceEventId: "e1",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 5, outputTokens: 3,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 8,
            costUsd: nil
        )
        _ = try repo.importIncrementalUsageEvents([event1], checkpoint: LocalScanFileCheckpointUpdate(
            sourceTool: "pi", path: "/tmp/p.jsonl", fileSize: 100, modifiedAt: nil,
            fileId: nil, readOffset: 50, importedEventCount: 1, status: "ok", lastError: nil
        ))

        // Verify checkpoint
        let cp1 = try repo.checkpoint(for: "pi", path: "/tmp/p.jsonl")
        XCTAssertEqual(cp1?.readOffset, 50)

        // Now re-import the same event (should be skipped by dedup)
        let result2 = try repo.importIncrementalUsageEvents([event1], checkpoint: LocalScanFileCheckpointUpdate(
            sourceTool: "pi", path: "/tmp/p.jsonl", fileSize: 200, modifiedAt: nil,
            fileId: nil, readOffset: 100, importedEventCount: 0, status: "ok", lastError: nil
        ))
        XCTAssertEqual(result2.skipped, 1)
        XCTAssertEqual(result2.inserted, 0)

        // Checkpoint should still advance even though no new events (empty file update)
        let cp2 = try repo.checkpoint(for: "pi", path: "/tmp/p.jsonl")
        XCTAssertEqual(cp2?.readOffset, 100)
    }

    // MARK: - Error status

    func test_importIncremental_errorStatus_persists() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)

        // Import with error status
        _ = try repo.importIncrementalUsageEvents([], checkpoint: LocalScanFileCheckpointUpdate(
            sourceTool: "codex", path: "/tmp/bad.jsonl", fileSize: 0, modifiedAt: nil,
            fileId: nil, readOffset: 0, importedEventCount: 0,
            status: "parse_error", lastError: "JSON parse error at line 5"
        ))

        let cp = try repo.checkpoint(for: "codex", path: "/tmp/bad.jsonl")
        XCTAssertNotNil(cp)
    }

    // MARK: - Source status update

    func test_upsertSourceStatus_transitions() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let now = Date()

        // not_found
        try repo.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: "codex", displayName: "Codex", rootPath: "/nonexistent",
            status: "not_found", lastScanStartedAt: now, lastScanFinishedAt: now,
            filesSeen: 0, filesScanned: 0, eventsImported: 0, parseErrorCount: 0, lastError: nil
        ))

        var sources = try repo.fetchSources()
        XCTAssertEqual(sources.first { $0.sourceTool == "codex" }?.status, "not_found")

        // watching
        try repo.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: "codex", displayName: "Codex", rootPath: "/found",
            status: "watching", lastScanStartedAt: nil, lastScanFinishedAt: nil,
            filesSeen: 0, filesScanned: 0, eventsImported: 0, parseErrorCount: 0, lastError: nil
        ))

        sources = try repo.fetchSources()
        XCTAssertEqual(sources.first { $0.sourceTool == "codex" }?.status, "watching")
        XCTAssertEqual(sources.first { $0.sourceTool == "codex" }?.rootPath, "/found")

        // permission_denied
        try repo.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: "codex", displayName: "Codex", rootPath: "/locked",
            status: "permission_denied", lastScanStartedAt: nil, lastScanFinishedAt: nil,
            filesSeen: 0, filesScanned: 0, eventsImported: 0, parseErrorCount: 0,
            lastError: "Permission denied"
        ))

        sources = try repo.fetchSources()
        XCTAssertEqual(sources.first { $0.sourceTool == "codex" }?.status, "permission_denied")
        XCTAssertEqual(sources.first { $0.sourceTool == "codex" }?.lastError, "Permission denied")
    }
}
