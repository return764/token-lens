import XCTest
@testable import TokenLensApp
import GRDB

final class TokenUsagesRepositoryTests: XCTestCase {

    var dbManager: DatabaseManager!

    override func setUp() {
        super.setUp()
        dbManager = try! DatabaseManager(kind: .inMemory)
    }

    // MARK: - TokenUsage model

    func test_tokenUsage_init_storesAllFields() {
        let createdAt = Date()
        let usage = TokenUsage(
            id: "u-1",
            agenticTool: "pi",
            providerId: "anthropic",
            model: "claude-sonnet-4-20250514",
            inputTokens: 100,
            outputTokens: 50,
            cachedInputTokens: 10,
            cacheWriteTokens: 5,
            reasoningTokens: 20,
            totalTokens: 185,
            costUsd: 0.003,
            createdAt: createdAt
        )

        XCTAssertEqual(usage.id, "u-1")
        XCTAssertEqual(usage.agenticTool, "pi")
        XCTAssertEqual(usage.providerId, "anthropic")
        XCTAssertEqual(usage.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(usage.inputTokens, 100)
        XCTAssertEqual(usage.outputTokens, 50)
        XCTAssertEqual(usage.cachedInputTokens, 10)
        XCTAssertEqual(usage.cacheWriteTokens, 5)
        XCTAssertEqual(usage.reasoningTokens, 20)
        XCTAssertEqual(usage.totalTokens, 185)
        XCTAssertEqual(usage.costUsd, 0.003)
        XCTAssertEqual(usage.createdAt, createdAt)
    }

    // MARK: - TokenUsagesRepository insert + fetch

    func test_insertAndFetch_recentTokenUsages() throws {
        let repo = TokenUsagesRepository(dbManager: dbManager)

        try repo.insert(TokenUsage(
            id: "u-1", agenticTool: "pi", providerId: "anthropic",
            model: "claude-sonnet-4-20250514",
            inputTokens: 100, outputTokens: 50, cachedInputTokens: 0,
            cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 150,
            costUsd: 0.003, createdAt: Date()
        ))
        try repo.insert(TokenUsage(
            id: "u-2", agenticTool: "codex", providerId: "openai",
            model: "gpt-4.1-mini",
            inputTokens: 200, outputTokens: 100, cachedInputTokens: 10,
            cacheWriteTokens: 5, reasoningTokens: 0, totalTokens: 315,
            costUsd: 0.0008, createdAt: Date()
        ))

        let recent = try repo.fetchRecent(limit: 10)
        XCTAssertEqual(recent.count, 2)
        // Most recent first
        XCTAssertEqual(recent[0].id, "u-2")
        XCTAssertEqual(recent[1].id, "u-1")
        XCTAssertEqual(recent[1].agenticTool, "pi")
        XCTAssertEqual(recent[1].totalTokens, 150)
    }

    func test_fetchRecent_respectsLimit() throws {
        let repo = TokenUsagesRepository(dbManager: dbManager)

        for i in 0..<5 {
            try repo.insert(TokenUsage(
                id: "u-\(i)", agenticTool: "pi", providerId: "anthropic",
                model: nil, inputTokens: i * 10, outputTokens: i * 5,
                cachedInputTokens: 0, cacheWriteTokens: 0, reasoningTokens: 0,
                totalTokens: i * 15, costUsd: 0, createdAt: Date()
            ))
        }

        let recent = try repo.fetchRecent(limit: 3)
        XCTAssertEqual(recent.count, 3)
    }

    func test_fetchMinuteAggregated_groupsBySingleMinute() throws {
        let repo = TokenUsagesRepository(dbManager: dbManager)

        try repo.insert(TokenUsage(
            id: "u-1", agenticTool: "codex", providerId: "openai",
            model: "gpt-5",
            inputTokens: 10, outputTokens: 5, cachedInputTokens: 2,
            cacheWriteTokens: 1, reasoningTokens: 0, totalTokens: 18,
            costUsd: 0.001, createdAt: try requireDate("2026-06-14T10:03:05Z")
        ))
        try repo.insert(TokenUsage(
            id: "u-2", agenticTool: "codex", providerId: "openai",
            model: "gpt-5",
            inputTokens: 20, outputTokens: 7, cachedInputTokens: 3,
            cacheWriteTokens: 0, reasoningTokens: 1, totalTokens: 31,
            costUsd: 0.002, createdAt: try requireDate("2026-06-14T10:03:55Z")
        ))
        try repo.insert(TokenUsage(
            id: "u-3", agenticTool: "codex", providerId: "openai",
            model: "gpt-5",
            inputTokens: 30, outputTokens: 9, cachedInputTokens: 4,
            cacheWriteTokens: 2, reasoningTokens: 0, totalTokens: 45,
            costUsd: 0.003, createdAt: try requireDate("2026-06-14T10:04:01Z")
        ))

        let buckets = try repo.fetchMinuteAggregated(
            source: "codex",
            provider: "openai",
            model: "gpt-5"
        )

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].minute, try requireDate("2026-06-14T10:03:00Z"))
        XCTAssertEqual(buckets[0].totalInputTokens, 30)
        XCTAssertEqual(buckets[0].totalOutputTokens, 12)
        XCTAssertEqual(buckets[0].totalCachedInputTokens, 5)
        XCTAssertEqual(buckets[0].totalCacheWriteTokens, 1)
        XCTAssertEqual(buckets[0].totalReasoningTokens, 1)
        XCTAssertEqual(buckets[0].totalTokens, 49)
        XCTAssertEqual(buckets[0].requestCount, 2)

        XCTAssertEqual(buckets[1].minute, try requireDate("2026-06-14T10:04:00Z"))
        XCTAssertEqual(buckets[1].totalInputTokens, 30)
        XCTAssertEqual(buckets[1].requestCount, 1)
    }

    func test_distinctOverviewFilters_respectSince() throws {
        let repo = TokenUsagesRepository(dbManager: dbManager)
        let now = Date()
        let oldDate = now.addingTimeInterval(-2 * 24 * 60 * 60)
        let since = now.addingTimeInterval(-60 * 60)

        try repo.insert(TokenUsage(
            id: "old-1", agenticTool: "pi", providerId: "anthropic",
            model: "claude-sonnet-4-20250514",
            inputTokens: 100, outputTokens: 50, cachedInputTokens: 0,
            cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 150,
            costUsd: 0.003, createdAt: oldDate
        ))
        try repo.insert(TokenUsage(
            id: "new-1", agenticTool: "codex", providerId: "openai",
            model: "gpt-5",
            inputTokens: 200, outputTokens: 100, cachedInputTokens: 10,
            cacheWriteTokens: 5, reasoningTokens: 0, totalTokens: 315,
            costUsd: 0.0008, createdAt: now
        ))

        XCTAssertEqual(try repo.fetchDistinctSources(since: since), ["codex"])
        XCTAssertEqual(try repo.fetchDistinctProviders(for: "codex", since: since), ["openai"])
        XCTAssertEqual(try repo.fetchDistinctModels(for: "codex", provider: "openai", since: since), ["gpt-5"])
        XCTAssertEqual(try repo.fetchDistinctProviders(for: "pi", since: since), [])
    }

    private func requireDate(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateCoding.parse(text))
    }
}
