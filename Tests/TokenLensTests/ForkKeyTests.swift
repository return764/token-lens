import XCTest
@testable import TokenLensApp

/// Tests for key-based dedup guaranteeing that the same usage event
/// (same key) across different files or after fork doesn't duplicate.
final class ForkKeyTests: XCTestCase {

    func test_sameKeyDifferentFile_notDuplicated() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        // Same usage appears in two different files after fork/copy
        let eventFileA = LocalUsageEvent(
            key: "pi:native:msg-1",
            sourceTool: "pi", sourceFile: "/path/a.jsonl", sourceEventId: "msg-1",
            sourceSessionId: "sess-a", sourceCwd: "/project-a", timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 100, outputTokens: 50,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 150,
            costUsd: nil
        )
        let eventFileB = LocalUsageEvent(
            key: "pi:native:msg-1",
            sourceTool: "pi", sourceFile: "/path/b.jsonl", sourceEventId: "msg-1",
            sourceSessionId: "sess-b", sourceCwd: "/project-b", timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 100, outputTokens: 50,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 150,
            costUsd: nil
        )

        // Import from file A
        let result1 = try repo.importUsageEvents([eventFileA])
        XCTAssertEqual(result1.inserted, 1)
        XCTAssertEqual(result1.skipped, 0)

        // Import same key from file B — should be skipped
        let result2 = try repo.importUsageEvents([eventFileB])
        XCTAssertEqual(result2.inserted, 0)
        XCTAssertEqual(result2.skipped, 1)

        let tokenRepo = TokenUsagesRepository(dbManager: dbManager)
        let recent = try tokenRepo.fetchRecent(limit: 10)
        XCTAssertEqual(recent.count, 1, "Should not duplicate across files")
    }

    func test_sameUsageDifferentSession_notDuplicated() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        // Claude Code usage event with same native id but different session
        let event1 = LocalUsageEvent(
            key: "claude_code:native:uuid-123",
            sourceTool: "claude_code", sourceFile: "/tmp/1.jsonl", sourceEventId: "uuid-123",
            sourceSessionId: "session-old", sourceCwd: "/work", timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 10, outputTokens: 5,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 15,
            costUsd: nil
        )
        let event2 = LocalUsageEvent(
            key: "claude_code:native:uuid-123",
            sourceTool: "claude_code", sourceFile: "/tmp/2.jsonl", sourceEventId: "uuid-123",
            sourceSessionId: "session-new", sourceCwd: "/work", timestamp: createdAt,
            providerId: "anthropic", model: "claude", inputTokens: 10, outputTokens: 5,
            cacheReadTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 15,
            costUsd: nil
        )

        _ = try repo.importUsageEvents([event1])
        let result = try repo.importUsageEvents([event2])
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.inserted, 0)
    }

    func test_codexUsageFingerprint_isFileIndependent() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = LocalScanRepository(dbManager: dbManager)
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T12:00:00Z"))

        // Codex events without id — rely on usage fingerprint
        let event1 = LocalUsageEvent(
            key: "codex:usage:abc123def",
            sourceTool: "codex", sourceFile: "/tmp/c1.jsonl", sourceEventId: "e1",
            sourceSessionId: "s1", sourceCwd: "/work", timestamp: createdAt,
            providerId: "openai", model: "gpt-5-codex", inputTokens: 100, outputTokens: 20,
            cacheReadTokens: 15, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 135,
            costUsd: nil
        )
        let event2 = LocalUsageEvent(
            key: "codex:usage:abc123def",
            sourceTool: "codex", sourceFile: "/tmp/c2.jsonl", sourceEventId: "e1",
            sourceSessionId: "s2", sourceCwd: "/other", timestamp: createdAt,
            providerId: "openai", model: "gpt-5-codex", inputTokens: 100, outputTokens: 20,
            cacheReadTokens: 15, cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 135,
            costUsd: nil
        )

        _ = try repo.importUsageEvents([event1])
        let result = try repo.importUsageEvents([event2])
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.inserted, 0)
    }
}
