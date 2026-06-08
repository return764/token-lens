import XCTest
@testable import TokenLensApp

final class CostCalculatorTests: XCTestCase {
    var dbManager: DatabaseManager!

    override func setUp() {
        super.setUp()
        dbManager = try! DatabaseManager(kind: .inMemory)
    }

    // MARK: - Happy path: valid pricing rule

    func test_calculatesCorrectCost_withValidPricingRule() throws {
        let pricingRepo = ModelsRepository(dbManager: dbManager)
        let calculator = CostCalculator(pricingRepo: pricingRepo)

        // Given: a pricing rule for a test model (not in seed)
        try pricingRepo.insert(PricingRule(
            id: "rule-1",
            providerId: "openai",
            model: "gpt-4.1-mini-test",
            inputPrice: 0.40,
            outputPrice: 1.60,
            cachedInputPrice: 0.20,
            reasoningPrice: 0,
            currency: "USD",
            effectiveFrom: "2025-01-01",
            effectiveTo: nil
        ))

        // When: calculating cost for 1000 input and 500 output tokens
        let input = CostInput(
            providerId: "openai",
            model: "gpt-4.1-mini-test",
            inputTokens: 1000,
            outputTokens: 500,
            cachedInputTokens: 0,
            reasoningTokens: 0,
            createdAt: Date()
        )
        let result = try calculator.calculate(input)

        // Then: pricing found and cost matches formula
        XCTAssertTrue(result.pricingFound, "Should find matching pricing rule")
        // input:  1000 / 1_000_000 * 0.40 = 0.0004
        // output:  500 / 1_000_000 * 1.60 = 0.0008
        // total: 0.0012
        XCTAssertEqual(result.costUsd, 0.0012, accuracy: 0.00001)
    }

    // MARK: - No matching rule

    func test_returnsPricingNotFound_whenNoMatchingRule() throws {
        let pricingRepo = ModelsRepository(dbManager: dbManager)
        let calculator = CostCalculator(pricingRepo: pricingRepo)

        // Given: no pricing rules for this model
        let input = CostInput(
            providerId: "openai",
            model: "unknown-model",
            inputTokens: 1000,
            outputTokens: 500,
            cachedInputTokens: 0,
            reasoningTokens: 0,
            createdAt: Date()
        )

        // When
        let result = try calculator.calculate(input)

        // Then
        XCTAssertFalse(result.pricingFound, "Should not find pricing for unknown model")
        XCTAssertEqual(result.costUsd, 0, "Cost should be 0 when pricing not found")
    }

    // MARK: - Effective date range

    func test_respectsEffectiveDateRange() throws {
        let pricingRepo = ModelsRepository(dbManager: dbManager)
        let calculator = CostCalculator(pricingRepo: pricingRepo)

        // Given: a rule effective between 2025-01-01 and 2025-06-30 (using unique model)
        try pricingRepo.insert(PricingRule(
            id: "rule-2",
            providerId: "openai",
            model: "date-range-test",
            inputPrice: 0.40,
            outputPrice: 1.60,
            cachedInputPrice: 0.20,
            reasoningPrice: 0,
            currency: "USD",
            effectiveFrom: "2025-01-01",
            effectiveTo: "2025-06-30"
        ))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // When: a call within the effective range
        let inRangeDate = dateFormatter.date(from: "2025-03-15")!
        let resultInRange = try calculator.calculate(CostInput(
            providerId: "openai",
            model: "date-range-test",
            inputTokens: 1000,
            outputTokens: 0,
            cachedInputTokens: 0,
            reasoningTokens: 0,
            createdAt: inRangeDate
        ))
        XCTAssertTrue(resultInRange.pricingFound, "Should find rule for date within range")

        // When: a call outside the effective range
        let outOfRangeDate = dateFormatter.date(from: "2025-08-01")!
        let resultOutOfRange = try calculator.calculate(CostInput(
            providerId: "openai",
            model: "date-range-test",
            inputTokens: 1000,
            outputTokens: 0,
            cachedInputTokens: 0,
            reasoningTokens: 0,
            createdAt: outOfRangeDate
        ))
        XCTAssertFalse(resultOutOfRange.pricingFound, "Should NOT find rule for date outside range")
    }

    // MARK: - All token dimensions

    func test_calculatesAllTokenDimensionsCorrectly() throws {
        let pricingRepo = ModelsRepository(dbManager: dbManager)
        let calculator = CostCalculator(pricingRepo: pricingRepo)

        // Given: a pricing rule with all dimension prices set (unique model not in seed)
        try pricingRepo.insert(PricingRule(
            id: "rule-3",
            providerId: "test",
            model: "multi-dimension-test",
            inputPrice: 3.00,
            outputPrice: 15.00,
            cachedInputPrice: 0.30,
            reasoningPrice: 8.00,
            currency: "USD",
            effectiveFrom: "2025-01-01",
            effectiveTo: nil
        ))

        // When: a call with all token types present
        let input = CostInput(
            providerId: "test",
            model: "multi-dimension-test",
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cachedInputTokens: 200_000,
            reasoningTokens: 100_000,
            createdAt: Date()
        )
        let result = try calculator.calculate(input)

        // Then: each dimension contributes correctly
        // input:    1_000_000 / 1_000_000 * 3.00 = 3.00
        // output:     500_000 / 1_000_000 * 15.00 = 7.50
        // cached:     200_000 / 1_000_000 * 0.30 = 0.06
        // reasoning:  100_000 / 1_000_000 * 8.00 = 0.80
        // total: 11.36
        XCTAssertTrue(result.pricingFound)
        XCTAssertEqual(result.costUsd, 11.36, accuracy: 0.0001)
    }
}
