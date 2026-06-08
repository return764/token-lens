import Foundation

/// A single token usage record from an agentic tool.
public struct TokenUsage: Identifiable {
    public let id: String
    public let agenticTool: String
    public let providerId: String
    public let model: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteTokens: Int
    public let reasoningTokens: Int
    public let totalTokens: Int
    public let costUsd: Double
    public let createdAt: Date

    public init(id: String, agenticTool: String, providerId: String, model: String?, inputTokens: Int, outputTokens: Int, cachedInputTokens: Int, cacheWriteTokens: Int, reasoningTokens: Int, totalTokens: Int, costUsd: Double, createdAt: Date) {
        self.id = id
        self.agenticTool = agenticTool
        self.providerId = providerId
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.reasoningTokens = reasoningTokens
        self.totalTokens = totalTokens
        self.costUsd = costUsd
        self.createdAt = createdAt
    }
}
