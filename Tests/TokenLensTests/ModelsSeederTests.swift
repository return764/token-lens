import XCTest
@testable import TokenLensApp

// MARK: - Mock API

private struct MockModelsDevAPI: ModelsDevAPI {
    let response: ModelsDevResponse
    let shouldThrow: Bool

    init(response: ModelsDevResponse, shouldThrow: Bool = false) {
        self.response = response
        self.shouldThrow = shouldThrow
    }

    func fetchProviders() async throws -> ModelsDevResponse {
        if shouldThrow { throw ModelsDevAPIError.invalidResponse }
        return response
    }
}

// MARK: - Helpers

private func makeProvider(slug: String, models: [String: ModelsDevModel]) -> ModelsDevProvider {
    ModelsDevProvider(id: slug, name: slug.uppercased(), models: models)
}

private func makeModel(id: String, inputPrice: Double, outputPrice: Double, cacheRead: Double? = nil) -> ModelsDevModel {
    ModelsDevModel(id: id, name: id, cost: ModelsDevCost(input: inputPrice, output: outputPrice, cacheRead: cacheRead))
}

private func makeModelNoCost(id: String) -> ModelsDevModel {
    ModelsDevModel(id: id, name: id, cost: nil)
}

// MARK: - Tests

final class ModelsSeederTests: XCTestCase {
    var dbManager: DatabaseManager!
    var modelsRepo: ModelsRepository!
    var settingsRepo: SettingsRepository!

    override func setUp() {
        super.setUp()
        dbManager = try! DatabaseManager(kind: .inMemory)
        modelsRepo = ModelsRepository(dbManager: dbManager)
        settingsRepo = SettingsRepository(dbManager: dbManager)
    }

    // MARK: - Happy path

    func test_seedIfNeeded_populatesEmptyModelsTable() async throws {
        // Given: models table is empty
        try modelsRepo.deleteAll()
        XCTAssertTrue(try modelsRepo.fetchAll().isEmpty)

        // Given: mock API returns 2 providers with 3 models total
        let mockResponse: ModelsDevResponse = [
            "openai": makeProvider(slug: "openai", models: [
                "gpt-4o": makeModel(id: "gpt-4o", inputPrice: 2.50, outputPrice: 10.00),
                "gpt-4.1-mini": makeModel(id: "gpt-4.1-mini", inputPrice: 0.40, outputPrice: 1.60, cacheRead: 0.20),
            ]),
            "anthropic": makeProvider(slug: "anthropic", models: [
                "claude-sonnet-4": makeModel(id: "claude-sonnet-4", inputPrice: 3.00, outputPrice: 15.00),
            ]),
        ]
        let mockAPI = MockModelsDevAPI(response: mockResponse)
        let seeder = ModelsSeeder(api: mockAPI, modelsRepo: modelsRepo, settingsRepo: settingsRepo)

        // When
        try await seeder.seedIfNeeded()

        // Then: all 3 models are inserted
        let all = try modelsRepo.fetchAll()
        XCTAssertEqual(all.count, 3)

        // Then: verify one specific rule
        let gpt4o = try modelsRepo.find(providerId: "openai", model: "gpt-4o", date: "2026-01-01")
        XCTAssertNotNil(gpt4o)
        XCTAssertEqual(gpt4o?.inputPrice, 2.50)
        XCTAssertEqual(gpt4o?.outputPrice, 10.00)
        XCTAssertEqual(gpt4o?.cachedInputPrice, 0.0)
        XCTAssertEqual(gpt4o?.reasoningPrice, 0.0)

        // Then: verify cached input price flows through
        let mini = try modelsRepo.find(providerId: "openai", model: "gpt-4.1-mini", date: "2026-01-01")
        XCTAssertEqual(mini?.cachedInputPrice, 0.20)
    }

    // MARK: - Filter models without cost

    func test_seedIfNeeded_skipsModelsWithoutCost() async throws {
        // Given: models table is empty
        try modelsRepo.deleteAll()

        // Given: one model with cost, one without
        let mockResponse: ModelsDevResponse = [
            "openai": makeProvider(slug: "openai", models: [
                "paid-model": makeModel(id: "paid-model", inputPrice: 1.0, outputPrice: 2.0),
                "free-model": makeModelNoCost(id: "free-model"),
            ]),
        ]
        let mockAPI = MockModelsDevAPI(response: mockResponse)
        let seeder = ModelsSeeder(api: mockAPI, modelsRepo: modelsRepo, settingsRepo: settingsRepo)

        // When
        try await seeder.seedIfNeeded()

        // Then: only the paid model is inserted
        let all = try modelsRepo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].model, "paid-model")
    }

    // MARK: - Failure path

    func test_seedIfNeeded_clearsModelsAndRecordsFailedOnAPIError() async throws {
        // Given: models table is empty (seeder only runs when empty)
        try modelsRepo.deleteAll()
        XCTAssertTrue(try modelsRepo.fetchAll().isEmpty)

        // Given: API throws
        let mockAPI = MockModelsDevAPI(response: [:], shouldThrow: true)
        let seeder = ModelsSeeder(api: mockAPI, modelsRepo: modelsRepo, settingsRepo: settingsRepo)

        // When
        do {
            try await seeder.seedIfNeeded()
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }

        // Then: models table is cleared
        let all = try modelsRepo.fetchAll()
        XCTAssertTrue(all.isEmpty, "Models table should be empty after failed seed")

        // Then: last_synced_at is recorded as "failed"
        let syncedAt = try settingsRepo.fetch("last_synced_at")
        XCTAssertEqual(syncedAt, "failed")
    }

    // MARK: - Idempotent

    func test_seedIfNeeded_skipsWhenModelsAlreadyExist() async throws {
        // Given: models table already has data
        try modelsRepo.insert(PricingRule(
            id: "existing-1", providerId: "openai", model: "existing-model",
            inputPrice: 5.0, outputPrice: 10.0,
            cachedInputPrice: 0, reasoningPrice: 0,
            currency: "USD", effectiveFrom: "2025-01-01", effectiveTo: nil
        ))
        let seedCount = try modelsRepo.fetchAll().count
        XCTAssertGreaterThan(seedCount, 0)
        let originalModels = try modelsRepo.fetchAll()

        // Given: mock API would return different data
        let mockResponse: ModelsDevResponse = [
            "openai": makeProvider(slug: "openai", models: [
                "other-model": makeModel(id: "other-model", inputPrice: 99.0, outputPrice: 99.0),
            ]),
        ]
        let mockAPI = MockModelsDevAPI(response: mockResponse)
        let seeder = ModelsSeeder(api: mockAPI, modelsRepo: modelsRepo, settingsRepo: settingsRepo)

        // When
        try await seeder.seedIfNeeded()

        // Then: models unchanged (not replaced by API data)
        let all = try modelsRepo.fetchAll()
        XCTAssertEqual(all.count, seedCount)
        XCTAssertEqual(all.map(\.id).sorted(), originalModels.map(\.id).sorted())
    }

    // MARK: - Records synced_at

    func test_seedIfNeeded_recordsLastSyncedAt_onSuccess() async throws {
        // Given: models table is empty
        try modelsRepo.deleteAll()

        let mockResponse: ModelsDevResponse = [
            "openai": makeProvider(slug: "openai", models: [
                "gpt-4o": makeModel(id: "gpt-4o", inputPrice: 2.50, outputPrice: 10.00),
            ]),
        ]
        let mockAPI = MockModelsDevAPI(response: mockResponse)
        let seeder = ModelsSeeder(api: mockAPI, modelsRepo: modelsRepo, settingsRepo: settingsRepo)

        // When
        try await seeder.seedIfNeeded()

        // Then: last_synced_at is a valid ISO8601 timestamp (not "failed")
        let syncedAt = try settingsRepo.fetch("last_synced_at")
        XCTAssertNotNil(syncedAt)
        XCTAssertNotEqual(syncedAt, "failed")
        let formatter = ISO8601DateFormatter()
        XCTAssertNotNil(formatter.date(from: syncedAt!), "Should be valid ISO8601")
    }

    // MARK: - Duplicate ID handling

    func test_seedIfNeeded_deduplicatesByGeneratedID() async throws {
        // Given: models table is empty
        try modelsRepo.deleteAll()

        // Two models whose IDs (after safeIdFragment) collide:
        // "a/b.c" → "a-b-c"   and   "a.b/c" → "a-b-c"
        let mockResponse: ModelsDevResponse = [
            "p1": makeProvider(slug: "p1", models: [
                "ab-c": makeModel(id: "a/b.c", inputPrice: 1.0, outputPrice: 2.0),
                "ab.c": makeModel(id: "a.b/c", inputPrice: 99.0, outputPrice: 99.0),
            ]),
        ]
        let mockAPI = MockModelsDevAPI(response: mockResponse)
        let seeder = ModelsSeeder(api: mockAPI, modelsRepo: modelsRepo, settingsRepo: settingsRepo)

        // When
        try await seeder.seedIfNeeded()

        // Then: only one rule inserted (duplicate IDs skipped)
        let all = try modelsRepo.fetchAll()
        XCTAssertEqual(all.count, 1, "Duplicate IDs should be deduplicated")
    }
}
