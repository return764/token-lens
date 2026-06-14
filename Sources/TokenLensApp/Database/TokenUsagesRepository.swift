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


    // MARK: - Aggregation (Overview Chart)

    /// 按分钟聚合 token 用量。source/provider/model 必传。
    /// 返回按分钟升序排列的聚合记录。
    public func fetchMinuteAggregated(
        source: String,
        provider: String,
        model: String,
        since: Date? = nil,
        maxBuckets: Int = 60
    ) throws -> [MinuteAggregation] {
        try dbManager.reader.read { db in
            var sql = """
                SELECT
                  strftime('%Y-%m-%dT%H:%M:00Z', created_at) AS minute,
                  SUM(input_tokens)        AS total_input,
                  SUM(output_tokens)       AS total_output,
                  SUM(cached_input_tokens) AS total_cached_input,
                  SUM(cache_write_tokens)  AS total_cache_write,
                  SUM(reasoning_tokens)    AS total_reasoning,
                  SUM(total_tokens)        AS total_all,
                  SUM(cost_usd)           AS total_cost,
                  COUNT(*)                AS request_count
                FROM token_usages
                WHERE agentic_tool = ?
                  AND provider_id = ?
                  AND model = ?
                """
            var args = StatementArguments([source, provider, model])
            var values: [any DatabaseValueConvertible] = [source, provider, model]

            if let since = since {
                sql += " AND created_at >= ?"
                values.append(ISO8601DateCoding.string(from: since))
            }

            sql += """
                GROUP BY minute
                ORDER BY minute ASC
                LIMIT ?
                """
            values.append(maxBuckets)
            args = StatementArguments(values)

            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.compactMap(Self.minuteAggregationFromRow)
        }
    }

    /// 获取数据库中所有出现过的 agentic_tool（source）列表，按字母排序。
    public func fetchDistinctSources() throws -> [String] {
        try dbManager.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT DISTINCT agentic_tool FROM token_usages ORDER BY agentic_tool"
            )
            return rows.compactMap { $0["agentic_tool"] as String? }
        }
    }

    /// 获取指定 source 下出现过的 provider_id 列表，按字母排序。
    public func fetchDistinctProviders(for source: String) throws -> [String] {
        try dbManager.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT DISTINCT provider_id FROM token_usages WHERE agentic_tool = ? ORDER BY provider_id",
                arguments: [source]
            )
            return rows.compactMap { $0["provider_id"] as String? }
        }
    }

    /// 获取指定 source + provider 下出现过的 model 列表，按字母排序。
    public func fetchDistinctModels(for source: String, provider: String) throws -> [String] {
        try dbManager.reader.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT model FROM token_usages
                    WHERE agentic_tool = ? AND provider_id = ? AND model IS NOT NULL
                    ORDER BY model
                    """,
                arguments: [source, provider]
            )
            return rows.compactMap { $0["model"] as String? }
        }
    }

    // MARK: - Helpers

    private static func minuteAggregationFromRow(_ row: Row) -> MinuteAggregation? {
        guard let minuteStr = row["minute"] as String?,
              let minute = ISO8601DateCoding.parse(minuteStr) else {
            return nil
        }
        return MinuteAggregation(
            minute: minute,
            totalInputTokens: row["total_input"] ?? 0,
            totalOutputTokens: row["total_output"] ?? 0,
            totalCachedInputTokens: row["total_cached_input"] ?? 0,
            totalCacheWriteTokens: row["total_cache_write"] ?? 0,
            totalReasoningTokens: row["total_reasoning"] ?? 0,
            totalTokens: row["total_all"] ?? 0,
            totalCostUsd: row["total_cost"] ?? 0,
            requestCount: row["request_count"] ?? 0
        )
    }

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
