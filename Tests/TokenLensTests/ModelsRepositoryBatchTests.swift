import XCTest
@testable import TokenLensApp

final class ModelsRepositoryBatchTests: XCTestCase {
    var dbManager: DatabaseManager!

    override func setUp() {
        super.setUp()
        dbManager = try! DatabaseManager(kind: .inMemory)
    }

    // MARK: - Helpers

    private func seedOne() throws {
        try ModelsRepository(dbManager: dbManager).insert(PricingRule(
            id: "test-1", providerId: "openai", model: "gpt-4o",
            inputPrice: 2.50, outputPrice: 10.00,
            cachedInputPrice: 0, reasoningPrice: 0,
            currency: "USD", effectiveFrom: "2025-01-01", effectiveTo: nil
        ))
    }

    // MARK: - deleteAll

    func test_deleteAll_removesAllModels() throws {
        let repo = ModelsRepository(dbManager: dbManager)

        // Given: models table has data
        try seedOne()
        XCTAssertFalse(try repo.fetchAll().isEmpty, "Should have seed data")

        // When
        try repo.deleteAll()

        // Then
        XCTAssertTrue(try repo.fetchAll().isEmpty, "All models should be deleted")
    }

    // MARK: - replaceAll

    func test_replaceAll_replacesExistingModels() throws {
        let repo = ModelsRepository(dbManager: dbManager)

        // Given: some data exists
        try seedOne()
        XCTAssertEqual(try repo.fetchAll().count, 1)

        // When: replaceAll with new rules
        let newRules = [
            PricingRule(
                id: "r-a", providerId: "p1", model: "m1",
                inputPrice: 1.0, outputPrice: 2.0,
                cachedInputPrice: 0.0, reasoningPrice: 0.0,
                currency: "USD", effectiveFrom: "2025-01-01", effectiveTo: nil
            ),
            PricingRule(
                id: "r-b", providerId: "p2", model: "m2",
                inputPrice: 3.0, outputPrice: 4.0,
                cachedInputPrice: 0.5, reasoningPrice: 1.0,
                currency: "USD", effectiveFrom: "2025-01-01", effectiveTo: nil
            ),
        ]
        try repo.replaceAll(newRules)

        // Then: only new rules exist
        let allAfter = try repo.fetchAll()
        XCTAssertEqual(allAfter.count, 2)
        XCTAssertEqual(allAfter[0].id, "r-a")
        XCTAssertEqual(allAfter[1].id, "r-b")
    }

    func test_replaceAll_withEmptyArray_clearsTable() throws {
        let repo = ModelsRepository(dbManager: dbManager)

        // Given: some data exists
        try seedOne()
        XCTAssertEqual(try repo.fetchAll().count, 1)

        // When
        try repo.replaceAll([])

        // Then
        XCTAssertTrue(try repo.fetchAll().isEmpty)
    }
}
