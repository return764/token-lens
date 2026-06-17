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
struct BarSegment: Identifiable, Equatable {
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
        let minuteKey = Int(minute.timeIntervalSinceReferenceDate)
        return [
            BarSegment(id: "\(minuteKey)|input",  minute: minute, dimension: .input,  count: totalInputTokens),
            BarSegment(id: "\(minuteKey)|output", minute: minute, dimension: .output, count: totalOutputTokens),
            BarSegment(id: "\(minuteKey)|cached", minute: minute, dimension: .cached, count: totalCachedTokens),
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

// MARK: - Chart data cache

/// Precomputed data used by OverviewChartView's high-frequency hover path.
struct OverviewChartData: Equatable {
    let identity: OverviewChartDataIdentity
    let sortedBuckets: [MinuteAggregation]
    let sortedSegments: [BarSegment]

    init(buckets: [MinuteAggregation]) {
        sortedBuckets = buckets.sorted(by: { $0.minute < $1.minute })
        sortedSegments = sortedBuckets.flatMap { $0.toBarSegments() }
        identity = OverviewChartDataIdentity(buckets: sortedBuckets)
    }

    static func == (lhs: OverviewChartData, rhs: OverviewChartData) -> Bool {
        lhs.identity == rhs.identity
    }

    func nearestBucket(to date: Date, maximumDistance: TimeInterval) -> MinuteAggregation? {
        guard !sortedBuckets.isEmpty else {
            return nil
        }

        var low = 0
        var high = sortedBuckets.count
        while low < high {
            let middle = (low + high) / 2
            if sortedBuckets[middle].minute < date {
                low = middle + 1
            } else {
                high = middle
            }
        }

        let candidates = [low - 1, low].compactMap { index -> MinuteAggregation? in
            guard sortedBuckets.indices.contains(index) else {
                return nil
            }
            return sortedBuckets[index]
        }

        guard let nearest = candidates.min(by: {
            abs($0.minute.timeIntervalSince(date)) < abs($1.minute.timeIntervalSince(date))
        }) else {
            return nil
        }

        return abs(nearest.minute.timeIntervalSince(date)) <= maximumDistance ? nearest : nil
    }
}

struct OverviewChartDataIdentity: Equatable {
    let bucketCount: Int
    let firstMinute: Date?
    let lastMinute: Date?
    let valueHash: Int

    init(buckets: [MinuteAggregation]) {
        bucketCount = buckets.count
        firstMinute = buckets.first?.minute
        lastMinute = buckets.last?.minute

        var hasher = Hasher()
        for bucket in buckets {
            hasher.combine(bucket.minute)
            hasher.combine(bucket.totalInputTokens)
            hasher.combine(bucket.totalOutputTokens)
            hasher.combine(bucket.totalCachedInputTokens)
            hasher.combine(bucket.totalCacheWriteTokens)
            hasher.combine(bucket.totalReasoningTokens)
            hasher.combine(bucket.totalTokens)
            hasher.combine(bucket.totalCostUsd)
            hasher.combine(bucket.requestCount)
        }
        valueHash = hasher.finalize()
    }
}
