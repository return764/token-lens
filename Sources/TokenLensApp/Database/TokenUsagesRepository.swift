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

    public func fetchUsageTotals(since startDate: Date?) throws -> UsageTotals {
        try dbManager.reader.read { db in
            var sql = """
                SELECT
                  COALESCE(SUM(total_tokens), 0) AS total_tokens,
                  COALESCE(SUM(cost_usd), 0) AS total_cost
                FROM token_usages
                """
            var arguments: StatementArguments = []

            if let since = startDate {
                sql += " WHERE created_at >= ?"
                arguments = [ISO8601DateCoding.string(from: since)]
            }

            let row = try Row.fetchOne(db, sql: sql, arguments: arguments)
            return UsageTotals(
                totalTokens: row?["total_tokens"] ?? 0,
                costUsd: row?["total_cost"] ?? 0
            )
        }
    }

    public func fetchMenuUsages(since startDate: Date?, limit: Int = 12) throws -> [MenuUsage] {
        try dbManager.reader.read { db in
            var sql = """
                SELECT
                  agentic_tool,
                  provider_id,
                  COALESCE(model, 'unknown') AS display_model,
                  SUM(input_tokens) AS total_input,
                  SUM(output_tokens) AS total_output,
                  SUM(cached_input_tokens + cache_write_tokens) AS total_cache,
                  SUM(cost_usd) AS total_cost,
                  MAX(created_at) AS latest_created_at
                FROM token_usages
                """
            var values: [any DatabaseValueConvertible] = []

            if let since = startDate {
                sql += " WHERE created_at >= ?"
                values.append(ISO8601DateCoding.string(from: since))
            }

            sql += """

                GROUP BY agentic_tool, provider_id, display_model
                ORDER BY latest_created_at DESC, agentic_tool, provider_id, display_model
                LIMIT ?
                """
            values.append(limit)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values))
            return rows.map(Self.menuUsageFromRow)
        }
    }


    // MARK: - Aggregation (Overview Chart)

    /// Aggregate token usage by hour for the Dashboard overview chart.
    /// source/provider/model are required; bounds are inclusive `since`, exclusive `before`.
    public func fetchHourlyAggregated(
        source: String,
        provider: String,
        model: String,
        since: Date? = nil,
        before: Date? = nil,
        maxBuckets: Int = 24
    ) throws -> [OverviewBucket] {
        try dbManager.reader.read { db in
            var sql = """
                SELECT
                  strftime('%Y-%m-%dT%H:00:00Z', created_at) AS hour,
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
            var values: [any DatabaseValueConvertible] = [source, provider, model]

            if let since = since {
                sql += " AND created_at >= ?"
                values.append(ISO8601DateCoding.string(from: since))
            }

            if let before = before {
                sql += " AND created_at < ?"
                values.append(ISO8601DateCoding.string(from: before))
            }

            sql += """
                GROUP BY hour
                ORDER BY hour ASC
                LIMIT ?
                """
            values.append(maxBuckets)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values))
            return rows.compactMap(Self.hourAggregationFromRow)
        }
    }

    /// 获取数据库中所有出现过的 agentic_tool（source）列表，按字母排序。
    public func fetchDistinctSources(since: Date? = nil, before: Date? = nil) throws -> [String] {
        try dbManager.reader.read { db in
            var sql = "SELECT DISTINCT agentic_tool FROM token_usages"
            var values: [any DatabaseValueConvertible] = []
            var clauses: [String] = []

            if let since = since {
                clauses.append("created_at >= ?")
                values.append(ISO8601DateCoding.string(from: since))
            }

            if let before = before {
                clauses.append("created_at < ?")
                values.append(ISO8601DateCoding.string(from: before))
            }

            if !clauses.isEmpty {
                sql += " WHERE " + clauses.joined(separator: " AND ")
            }
            sql += " ORDER BY agentic_tool"

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values))
            return rows.compactMap { $0["agentic_tool"] as String? }
        }
    }

    /// 获取指定 source 下出现过的 provider_id 列表，按字母排序。
    public func fetchDistinctProviders(for source: String, since: Date? = nil, before: Date? = nil) throws -> [String] {
        try dbManager.reader.read { db in
            var sql = "SELECT DISTINCT provider_id FROM token_usages WHERE agentic_tool = ?"
            var values: [any DatabaseValueConvertible] = [source]

            if let since = since {
                sql += " AND created_at >= ?"
                values.append(ISO8601DateCoding.string(from: since))
            }

            if let before = before {
                sql += " AND created_at < ?"
                values.append(ISO8601DateCoding.string(from: before))
            }

            sql += " ORDER BY provider_id"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values))
            return rows.compactMap { $0["provider_id"] as String? }
        }
    }

    /// 获取指定 source + provider 下出现过的 model 列表，按字母排序。
    public func fetchDistinctModels(for source: String, provider: String, since: Date? = nil, before: Date? = nil) throws -> [String] {
        try dbManager.reader.read { db in
            var sql = """
                SELECT DISTINCT model FROM token_usages
                WHERE agentic_tool = ? AND provider_id = ? AND model IS NOT NULL
                """
            var values: [any DatabaseValueConvertible] = [source, provider]

            if let since = since {
                sql += " AND created_at >= ?"
                values.append(ISO8601DateCoding.string(from: since))
            }

            if let before = before {
                sql += " AND created_at < ?"
                values.append(ISO8601DateCoding.string(from: before))
            }

            sql += " ORDER BY model"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values))
            return rows.compactMap { $0["model"] as String? }
        }
    }

    // MARK: - Helpers

    private static func hourAggregationFromRow(_ row: Row) -> OverviewBucket? {
        guard let hourStr = row["hour"] as String?,
              let hour = ISO8601DateCoding.parse(hourStr) else {
            return nil
        }
        return OverviewBucket(
            hour: hour,
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

    private static func menuUsageFromRow(_ row: Row) -> MenuUsage {
        MenuUsage(
            agenticTool: row["agentic_tool"],
            providerId: row["provider_id"],
            model: row["display_model"],
            inputTokens: row["total_input"] ?? 0,
            outputTokens: row["total_output"] ?? 0,
            cacheTokens: row["total_cache"] ?? 0,
            costUsd: row["total_cost"] ?? 0,
            latestCreatedAt: ISO8601DateCoding.parse((row["latest_created_at"] as String?) ?? "") ?? Date()
        )
    }
}
