import Foundation

/// Seeds the models table from models.dev/api.json on first launch.
public final class ModelsSeeder {
    private let api: ModelsDevAPI
    private let modelsRepo: ModelsRepository
    private let settingsRepo: SettingsRepository

    public init(api: ModelsDevAPI, modelsRepo: ModelsRepository, settingsRepo: SettingsRepository) {
        self.api = api
        self.modelsRepo = modelsRepo
        self.settingsRepo = settingsRepo
    }

    /// Seeds pricing rules if the models table is empty.
    /// On API failure, clears the table and records last_synced_at = "failed".
    public func seedIfNeeded() async throws {
        // Skip if already populated
        let existing = try modelsRepo.fetchAll()
        guard existing.isEmpty else { return }

        let providers: ModelsDevResponse
        do {
            providers = try await api.fetchProviders()
        } catch {
            try modelsRepo.deleteAll()
            try settingsRepo.update("last_synced_at", value: "failed")
            throw error
        }

        let rules = Self.buildRules(from: providers)
        try modelsRepo.replaceAll(rules)

        let now = ISO8601DateFormatter().string(from: Date())
        try settingsRepo.update("last_synced_at", value: now)
    }

    // MARK: - Helpers

    private static let effectiveFrom = "2025-01-01"

    private static func buildRules(from response: ModelsDevResponse) -> [PricingRule] {
        // Use dict to deduplicate by generated ID (safeIdFragment can cause collisions)
        var rulesById: [String: PricingRule] = [:]

        for (slug, provider) in response {
            for (_, model) in provider.models {
                guard let cost = model.cost else { continue }
                let id = "\(slug.safeIdFragment)-\(model.id.safeIdFragment)"
                guard rulesById[id] == nil else { continue }  // skip duplicates
                let rule = PricingRule(
                    id: id,
                    providerId: slug,
                    model: model.id,
                    inputPrice: cost.input,
                    outputPrice: cost.output,
                    cachedInputPrice: cost.cacheRead ?? 0,
                    reasoningPrice: 0,
                    currency: "USD",
                    effectiveFrom: effectiveFrom,
                    effectiveTo: nil
                )
                rulesById[id] = rule
            }
        }

        return Array(rulesById.values)
    }
}

// MARK: - String helper

private extension String {
    /// Replaces characters unsuitable for ID fragments.
    var safeIdFragment: String {
        self.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
