import XCTest
@testable import TokenLensApp

final class LocalScanRepositoryTests: XCTestCase {

    // MARK: - agentic_tool field

    func test_importUsageEvents_usesAgenticToolField() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))
        let event = LocalUsageEvent(
            key: "pi:native:entry-1",
            sourceTool: "pi",
            sourceFile: "/tmp/pi.jsonl",
            sourceEventId: "entry-1",
            sourceSessionId: "session-1",
            sourceCwd: "/tmp/project",
            timestamp: createdAt,
            providerId: "anthropic",
            model: "claude-sonnet-4-20250514",
            inputTokens: 10,
            outputTokens: 20,
            cacheReadTokens: 3,
            cacheWriteTokens: 4,
            reasoningTokens: 5,
            totalTokens: 42,
            costUsd: 0.01
        )

        let result = try repo.importUsageEvents([event])
        XCTAssertEqual(result.inserted, 1)

        let tokenRepo = TokenUsagesRepository(dbManager: dbManager)
        let recent = try tokenRepo.fetchRecent(limit: 10)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].agenticTool, "pi")
        XCTAssertEqual(recent[0].providerId, "anthropic")
        XCTAssertEqual(recent[0].totalTokens, 42)
        XCTAssertEqual(recent[0].costUsd, 0.01)
        XCTAssertEqual(recent[0].cachedInputTokens, 3)
        XCTAssertEqual(recent[0].cacheWriteTokens, 4)
        XCTAssertEqual(recent[0].reasoningTokens, 5)
    }

    func test_importUsageEvents_calculatesCostFromPricingWhenMissing() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let pricingRepo = ModelsRepository(dbManager: dbManager)
        try pricingRepo.insert(PricingRule(
            id: "openai-gpt-5.4-test",
            providerId: "openai",
            model: "gpt-5.4",
            inputPrice: 2.5,
            outputPrice: 15,
            cachedInputPrice: 0.25,
            reasoningPrice: 0,
            currency: "USD",
            effectiveFrom: "2025-01-01",
            effectiveTo: nil
        ))

        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))
        let event = LocalUsageEvent(
            key: "codex:usage:gpt-5.4-test",
            sourceTool: "codex",
            sourceFile: "/tmp/codex.jsonl",
            sourceEventId: "e-1",
            sourceSessionId: "session-1",
            sourceCwd: "/tmp/project",
            timestamp: createdAt,
            providerId: "openai",
            model: "gpt-5.4",
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cacheReadTokens: 200_000,
            cacheWriteTokens: 0,
            reasoningTokens: 0,
            totalTokens: 1_700_000,
            costUsd: nil
        )

        let result = try repo.importUsageEvents([event])
        XCTAssertEqual(result.inserted, 1)

        let recent = try TokenUsagesRepository(dbManager: dbManager).fetchRecent(limit: 1)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].costUsd, 10.05, accuracy: 0.0001)
    }

    // MARK: - Key-based dedup

    func test_importUsageEvents_keyBasedDedup_skipsDuplicateKeys() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        let event1 = LocalUsageEvent(
            key: "codex:usage:abc123",
            sourceTool: "codex", sourceFile: "/tmp/c.jsonl", sourceEventId: "e1",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: "openai", model: "gpt-4", inputTokens: 10, outputTokens: 5,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 15,
            costUsd: nil
        )
        let event2 = LocalUsageEvent(
            key: "codex:usage:def456",
            sourceTool: "codex", sourceFile: "/tmp/c.jsonl", sourceEventId: "e2",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: "openai", model: "gpt-4", inputTokens: 20, outputTokens: 10,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 30,
            costUsd: nil
        )

        // First import: both inserted
        let first = try repo.importUsageEvents([event1, event2])
        XCTAssertEqual(first.inserted, 2)

        // Second import: both skipped (same keys)
        let second = try repo.importUsageEvents([event1, event2])
        XCTAssertEqual(second.skipped, 2)
        XCTAssertEqual(second.inserted, 0)

        let tokenRepo = TokenUsagesRepository(dbManager: dbManager)
        let recent = try tokenRepo.fetchRecent(limit: 10)
        XCTAssertEqual(recent.count, 2, "Should still have only 2 records")
    }

    func test_importIncrementalUsageEvents_respectsKeyDedupAndUpdatesCheckpoint() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        let event1 = LocalUsageEvent(
            key: "pi:native:e1",
            sourceTool: "pi", sourceFile: "/tmp/p.jsonl", sourceEventId: "e1",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 5, outputTokens: 3,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 8,
            costUsd: nil
        )
        let event2 = LocalUsageEvent(
            key: "pi:native:e2",
            sourceTool: "pi", sourceFile: "/tmp/p.jsonl", sourceEventId: "e2",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 10, outputTokens: 6,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 16,
            costUsd: nil
        )

        // Import event1 with checkpoint update
        let result1 = try repo.importIncrementalUsageEvents([event1], checkpoint: LocalScanFileCheckpointUpdate(
            sourceTool: "pi", path: "/tmp/p.jsonl", fileSize: 100, modifiedAt: nil,
            fileId: nil, readOffset: 50, importedEventCount: 1, status: "ok", lastError: nil
        ))
        XCTAssertEqual(result1.inserted, 1)

        // Import both — event1 should be skipped, event2 inserted
        let result2 = try repo.importIncrementalUsageEvents([event1, event2], checkpoint: LocalScanFileCheckpointUpdate(
            sourceTool: "pi", path: "/tmp/p.jsonl", fileSize: 200, modifiedAt: nil,
            fileId: nil, readOffset: 100, importedEventCount: 1, status: "ok", lastError: nil
        ))
        XCTAssertEqual(result2.inserted, 1)
        XCTAssertEqual(result2.skipped, 1)

        let tokenRepo = TokenUsagesRepository(dbManager: dbManager)
        let recent = try tokenRepo.fetchRecent(limit: 10)
        XCTAssertEqual(recent.count, 2)

        // Verify checkpoint was updated
        let checkpoint = try repo.checkpoint(for: "pi", path: "/tmp/p.jsonl")
        XCTAssertEqual(checkpoint?.readOffset, 100)
    }

    // MARK: - Checkpoint

    func test_checkpoint_returnsNilForUnknownFile() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)

        let cp = try repo.checkpoint(for: "codex", path: "/nonexistent.jsonl")
        XCTAssertNil(cp)
    }

    func test_checkpoint_returnsStoredCheckpoint() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let now = Date()

        // Write a checkpoint via importIncrementalUsageEvents with zero events
        _ = try repo.importIncrementalUsageEvents([], checkpoint: LocalScanFileCheckpointUpdate(
            sourceTool: "codex", path: "/tmp/test.jsonl", fileSize: 500, modifiedAt: now,
            fileId: "inode-123", readOffset: 200, importedEventCount: 0, status: "ok", lastError: nil
        ))

        let cp = try repo.checkpoint(for: "codex", path: "/tmp/test.jsonl")
        XCTAssertEqual(cp?.readOffset, 200)
        XCTAssertEqual(cp?.fileSize, 500)
        XCTAssertEqual(cp?.fileId, "inode-123")
    }

    // MARK: - Fallback provider

    func test_importUsageEvents_fallsBackProviderForAgenticTool() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        let piEvent = LocalUsageEvent(
            key: "pi:native:e1",
            sourceTool: "pi", sourceFile: "/tmp/pi.jsonl", sourceEventId: "e1",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: nil, model: nil, inputTokens: 1, outputTokens: 2,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 3,
            costUsd: nil
        )
        let codexEvent = LocalUsageEvent(
            key: "codex:usage:abc",
            sourceTool: "codex", sourceFile: "/tmp/codex.jsonl", sourceEventId: "e1",
            sourceSessionId: nil, sourceCwd: nil, timestamp: createdAt,
            providerId: nil, model: nil, inputTokens: 4, outputTokens: 5,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 9,
            costUsd: nil
        )

        _ = try repo.importUsageEvents([piEvent, codexEvent])

        let tokenRepo = TokenUsagesRepository(dbManager: dbManager)
        let recent = try tokenRepo.fetchRecent(limit: 10)
        let providerIds = recent.map(\.providerId).sorted()
        XCTAssertEqual(providerIds, ["anthropic", "openai"])
    }

    // MARK: - Source/file status persistence (unchanged behavior)

    func test_sourceAndFileStatusesArePersisted() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let now = Date()

        try repo.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: "codex",
            displayName: "Codex",
            rootPath: "/missing",
            status: "not_found",
            lastScanStartedAt: now,
            lastScanFinishedAt: now,
            filesSeen: 0,
            filesScanned: 0,
            eventsImported: 0,
            parseErrorCount: 0,
            lastError: nil
        ))
        try repo.upsertFileStatus(LocalScanFileStatus(
            sourceTool: "codex",
            path: "/tmp/codex.jsonl",
            fileSize: 123,
            modifiedAt: now,
            lastScannedAt: now,
            importedEventCount: 2,
            status: "ok",
            lastError: nil
        ))

        let sources = try repo.fetchSources()
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources[0].sourceTool, "codex")
        XCTAssertEqual(sources[0].status, "not_found")
        XCTAssertFalse(try repo.shouldScanFile(sourceTool: "codex", url: URL(fileURLWithPath: "/tmp/codex.jsonl")))
    }
}
