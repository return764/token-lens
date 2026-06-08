import Foundation
import GRDB

/// Repository for token_usages CRUD.
public final class TokenUsagesRepository {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    /// Insert a single token usage record.
    public func insert(_ usage: TokenUsage) throws {
        let iso = ISO8601DateCoding.string(from: usage.createdAt)
        try dbManager.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO token_usages
                    (id, agentic_tool, provider_id, model,
                     input_tokens, output_tokens, cached_input_tokens, cache_write_tokens,
                     reasoning_tokens, total_tokens, cost_usd, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    usage.id, usage.agenticTool, usage.providerId, usage.model,
                    usage.inputTokens, usage.outputTokens, usage.cachedInputTokens, usage.cacheWriteTokens,
                    usage.reasoningTokens, usage.totalTokens, usage.costUsd, iso
                ]
            )
        }
    }

    /// Fetch the most recent token usages.
    public func fetchRecent(limit: Int) throws -> [TokenUsage] {
        try dbManager.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM token_usages ORDER BY created_at DESC LIMIT ?",
                arguments: [limit]
            )
            return rows.map(Self.tokenUsageFromRow)
        }
    }

    /// Fetch token usages since a given date (inclusive). Pass nil for all time.
    public func fetchUsages(since startDate: Date?) throws -> [TokenUsage] {
        try dbManager.reader.read { db in
            if let since = startDate {
                let iso = ISO8601DateCoding.string(from: since)
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM token_usages WHERE created_at >= ? ORDER BY created_at DESC",
                    arguments: [iso]
                )
                return rows.map(Self.tokenUsageFromRow)
            } else {
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM token_usages ORDER BY created_at DESC"
                )
                return rows.map(Self.tokenUsageFromRow)
            }
        }
    }


    // MARK: - Helpers

    private static func tokenUsageFromRow(_ row: Row) -> TokenUsage {
        return TokenUsage(
            id: row["id"],
            agenticTool: row["agentic_tool"],
            providerId: row["provider_id"],
            model: row["model"],
            inputTokens: row["input_tokens"],
            outputTokens: row["output_tokens"],
            cachedInputTokens: row["cached_input_tokens"],
            cacheWriteTokens: row["cache_write_tokens"],
            reasoningTokens: row["reasoning_tokens"],
            totalTokens: row["total_tokens"],
            costUsd: row["cost_usd"],
            createdAt: ISO8601DateCoding.parse((row["created_at"] as String?) ?? "") ?? Date()
        )
    }
}
