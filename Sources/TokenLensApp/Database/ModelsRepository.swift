import Foundation
import GRDB

/// Repository for models lookup.
public final class ModelsRepository {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    /// Insert a pricing rule.
    public func insert(_ rule: PricingRule) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try dbManager.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO models
                    (id, provider_id, model, input_price, output_price,
                     cached_input_price, reasoning_price,
                     currency, effective_from, effective_to, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    rule.id, rule.providerId, rule.model,
                    rule.inputPrice, rule.outputPrice,
                    rule.cachedInputPrice, rule.reasoningPrice,
                    rule.currency, rule.effectiveFrom, rule.effectiveTo, now
                ]
            )
        }
    }

    /// Find the applicable pricing rule for a provider/model on a given date.
    /// Returns nil if no matching rule is found.
    public func find(providerId: String, model: String, date: String) throws -> PricingRule? {
        try dbManager.reader.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM models
                WHERE provider_id = ? AND model = ?
                  AND effective_from <= ?
                  AND (effective_to IS NULL OR effective_to >= ?)
                ORDER BY effective_from DESC
                LIMIT 1
                """, arguments: [providerId, model, date, date])
            guard let row else { return nil }
            return pricingRuleFromRow(row)
        }
    }

    /// Fetch all pricing rules.
    public func fetchAll() throws -> [PricingRule] {
        try dbManager.reader.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM models ORDER BY provider_id, model")
            return rows.map(pricingRuleFromRow)
        }
    }

    /// Delete all pricing rules.
    public func deleteAll() throws {
        try dbManager.writer.write { db in
            try db.execute(sql: "DELETE FROM models")
        }
    }

    /// Atomically replace all pricing rules: delete all, then insert batch.
    public func replaceAll(_ rules: [PricingRule]) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try dbManager.writer.write { db in
            try db.execute(sql: "DELETE FROM models")
            for rule in rules {
                try db.execute(
                    sql: """
                        INSERT INTO models
                        (id, provider_id, model, input_price, output_price,
                         cached_input_price, reasoning_price,
                         currency, effective_from, effective_to, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        rule.id, rule.providerId, rule.model,
                        rule.inputPrice, rule.outputPrice,
                        rule.cachedInputPrice, rule.reasoningPrice,
                        rule.currency, rule.effectiveFrom, rule.effectiveTo, now
                    ]
                )
            }
        }
    }

    // MARK: - Helpers

    private func pricingRuleFromRow(_ row: Row) -> PricingRule {
        PricingRule(
            id: row["id"],
            providerId: row["provider_id"],
            model: row["model"],
            inputPrice: row["input_price"],
            outputPrice: row["output_price"],
            cachedInputPrice: row["cached_input_price"],
            reasoningPrice: row["reasoning_price"],
            currency: row["currency"],
            effectiveFrom: row["effective_from"],
            effectiveTo: row["effective_to"]
        )
    }
}
