import Foundation
import CryptoKit

/// Builds stable, deduplication-safe keys for LocalUsageEvent.
public enum LocalUsageKeyBuilder {

    /// Build a key using native stable id if available, otherwise usage fingerprint hash.
    public static func build(
        sourceTool: String,
        nativeId: String?,
        timestamp: Date,
        providerId: String?,
        model: String?,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int,
        costUsd: Double?
    ) -> String {
        if let nativeId, !nativeId.isEmpty {
            return "\(sourceTool):native:\(nativeId)"
        }
        let fingerprint = usageFingerprint(
            sourceTool: sourceTool,
            timestamp: timestamp,
            providerId: providerId,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            reasoningTokens: reasoningTokens,
            totalTokens: totalTokens,
            costUsd: costUsd
        )
        return "\(sourceTool):usage:\(fingerprint)"
    }

    // MARK: - Canonical usage fingerprint

    private static func isoString(from date: Date) -> String {
        ISO8601DateCoding.string(from: date)
    }

    private static func usageFingerprint(
        sourceTool: String,
        timestamp: Date,
        providerId: String?,
        model: String?,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int,
        reasoningTokens: Int,
        totalTokens: Int,
        costUsd: Double?
    ) -> String {
        // Canonical representation in fixed field order.
        // Deliberately excludes: source_file, source_cwd, line_number, read_offset,
        // raw prompt/response/tool output.
        var parts: [String] = []
        parts.append("source_tool=\(sourceTool)")
        parts.append("timestamp=\(isoString(from: timestamp))")
        parts.append("provider_id=\(providerId ?? "")")
        parts.append("model=\(model ?? "")")
        parts.append("input_tokens=\(inputTokens)")
        parts.append("output_tokens=\(outputTokens)")
        parts.append("cached_input_tokens=\(cacheReadTokens)")
        parts.append("cache_write_tokens=\(cacheWriteTokens)")
        parts.append("reasoning_tokens=\(reasoningTokens)")
        parts.append("total_tokens=\(totalTokens)")

        if let cost = costUsd {
            // Fixed 6 decimal places for canonical representation
            parts.append("cost_usd=\(String(format: "%.6f", cost))")
        } else {
            parts.append("cost_usd=0.000000")
        }

        let canonical = parts.joined(separator: "\n")
        guard let data = canonical.data(using: .utf8) else {
            return "hash_error"
        }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Convenience helper: build key from a usage dictionary (used by Codex adapter).
    public static func buildFromUsageDict(
        sourceTool: String,
        nativeId: String?,
        timestamp: Date,
        providerId: String?,
        model: String?,
        usage: [String: Any]
    ) -> String {
        let input = LocalRecordJSON.int(usage, "input_tokens")
        let output = LocalRecordJSON.int(usage, "output_tokens")
        let cacheRead = LocalRecordJSON.int(usage, "cached_input_tokens")
        let cacheWrite = LocalRecordJSON.int(usage, "cache_write_tokens")
        let reasoning = LocalRecordJSON.int(usage, "reasoning_output_tokens")
        let total = LocalRecordJSON.int(usage, "total_tokens")
        let cost = LocalRecordJSON.double(usage, "cost_usd")

        return build(
            sourceTool: sourceTool,
            nativeId: nativeId,
            timestamp: timestamp,
            providerId: providerId,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            reasoningTokens: reasoning,
            totalTokens: total,
            costUsd: cost
        )
    }
}
