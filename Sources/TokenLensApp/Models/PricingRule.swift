import Foundation

/// A pricing rule for a specific provider/model combination.
public struct PricingRule: Identifiable {
    public let id: String
    public let providerId: String
    public let model: String
    public let inputPrice: Double
    public let outputPrice: Double
    public let cachedInputPrice: Double
    public let reasoningPrice: Double
    public let currency: String
    public let effectiveFrom: String
    public let effectiveTo: String?

    public init(
        id: String, providerId: String, model: String,
        inputPrice: Double, outputPrice: Double,
        cachedInputPrice: Double, reasoningPrice: Double,
        currency: String, effectiveFrom: String, effectiveTo: String?
    ) {
        self.id = id
        self.providerId = providerId
        self.model = model
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.cachedInputPrice = cachedInputPrice
        self.reasoningPrice = reasoningPrice
        self.currency = currency
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
    }
}
