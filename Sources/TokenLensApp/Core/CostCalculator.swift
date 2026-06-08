import Foundation

/// Input for cost calculation.
public struct CostInput {
    public let providerId: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let reasoningTokens: Int
    public let createdAt: Date

    public init(providerId: String, model: String, inputTokens: Int, outputTokens: Int, cachedInputTokens: Int, reasoningTokens: Int, createdAt: Date) {
        self.providerId = providerId
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningTokens = reasoningTokens
        self.createdAt = createdAt
    }
}

/// Result of cost calculation.
public struct CostResult {
    public let costUsd: Double
    public let pricingFound: Bool

    public init(costUsd: Double, pricingFound: Bool) {
        self.costUsd = costUsd
        self.pricingFound = pricingFound
    }
}

/// Calculates the USD cost of an LLM call based on pricing rules.
public final class CostCalculator {
    private let pricingRepo: ModelsRepository

    public init(pricingRepo: ModelsRepository) {
        self.pricingRepo = pricingRepo
    }

    /// Calculate the cost for a given input. Returns a CostResult.
    /// If no matching pricing rule is found, returns costUsd=0 and pricingFound=false.
    public func calculate(_ input: CostInput) throws -> CostResult {
        let dateStr = dateString(from: input.createdAt)

        guard let rule = try pricingRepo.find(
            providerId: input.providerId,
            model: input.model,
            date: dateStr
        ) else {
            return CostResult(costUsd: 0, pricingFound: false)
        }

        let cost =
            Double(input.inputTokens) / 1_000_000.0 * rule.inputPrice
            + Double(input.outputTokens) / 1_000_000.0 * rule.outputPrice
            + Double(input.cachedInputTokens) / 1_000_000.0 * rule.cachedInputPrice
            + Double(input.reasoningTokens) / 1_000_000.0 * rule.reasoningPrice

        return CostResult(costUsd: cost, pricingFound: true)
    }

    // MARK: - Helpers

    private func dateString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
