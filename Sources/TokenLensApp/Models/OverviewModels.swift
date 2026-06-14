import Foundation
import SwiftUI
import Charts

// MARK: - MinuteAggregation (宽表：DB 聚合结果)

/// 单个分钟桶的聚合数据（宽表格式，一条记录包含所有维度）。
public struct MinuteAggregation: Identifiable, Equatable {
    public let minute: Date
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCachedInputTokens: Int
    public let totalCacheWriteTokens: Int
    public let totalReasoningTokens: Int
    public let totalTokens: Int
    public let totalCostUsd: Double
    public let requestCount: Int

    public var id: Date { minute }
    public var totalCachedTokens: Int { totalCachedInputTokens + totalCacheWriteTokens }

    public init(
        minute: Date,
        totalInputTokens: Int,
        totalOutputTokens: Int,
        totalCachedInputTokens: Int,
        totalCacheWriteTokens: Int,
        totalReasoningTokens: Int,
        totalTokens: Int,
        totalCostUsd: Double,
        requestCount: Int
    ) {
        self.minute = minute
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCachedInputTokens = totalCachedInputTokens
        self.totalCacheWriteTokens = totalCacheWriteTokens
        self.totalReasoningTokens = totalReasoningTokens
        self.totalTokens = totalTokens
        self.totalCostUsd = totalCostUsd
        self.requestCount = requestCount
    }
}

// MARK: - BarSegment (长表：Chart 堆叠数据)

/// 单个分钟桶内的单条维度数据（供 Swift Charts 堆叠柱状图使用）。
struct BarSegment: Identifiable {
    let id: String       // "minute|dimension"，如 "2026-06-14T14:01:00|input"
    let minute: Date
    let dimension: TokenDimension
    let count: Int
}

/// Token 维度枚举，用作 Chart 的 series / foreground style key。
enum TokenDimension: String, CaseIterable, Plottable {
    case input
    case output
    case cached

    var label: String {
        switch self {
        case .input:  return "Input"
        case .output: return "Output"
        case .cached: return "Cached"
        }
    }

    var color: Color {
        switch self {
        case .input:  return .blue
        case .output: return .green
        case .cached: return .orange
        }
    }
}

// MARK: - 宽表 → 长表转换

extension MinuteAggregation {
    /// 将一个 MinuteAggregation 拆成 3 个 BarSegment（input / output / cached），
    /// 用于 Swift Charts 堆叠柱状图。
    func toBarSegments() -> [BarSegment] {
        let iso = ISO8601DateFormatter().string(from: minute)
        return [
            BarSegment(id: "\(iso)|input",  minute: minute, dimension: .input,  count: totalInputTokens),
            BarSegment(id: "\(iso)|output", minute: minute, dimension: .output, count: totalOutputTokens),
            BarSegment(id: "\(iso)|cached", minute: minute, dimension: .cached, count: totalCachedTokens),
        ]
    }
}

extension Array where Element == MinuteAggregation {
    /// 将所有 MinuteAggregation 转为 BarSegment 集合，并按时间升序排列。
    func toBarSegments() -> [BarSegment] {
        self.sorted(by: { $0.minute < $1.minute })
            .flatMap { $0.toBarSegments() }
    }
}
