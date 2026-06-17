import Foundation
import SwiftUI
import Charts

// MARK: - OverviewBucket (wide table: DB aggregation result)

/// Single hourly overview bucket with all tracked token dimensions.
public struct OverviewBucket: Identifiable, Equatable {
    public let hour: Date
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCachedInputTokens: Int
    public let totalCacheWriteTokens: Int
    public let totalReasoningTokens: Int
    public let totalTokens: Int
    public let totalCostUsd: Double
    public let requestCount: Int

    public var id: Date { hour }
    public var totalCachedTokens: Int { totalCachedInputTokens + totalCacheWriteTokens }

    public init(
        hour: Date,
        totalInputTokens: Int,
        totalOutputTokens: Int,
        totalCachedInputTokens: Int,
        totalCacheWriteTokens: Int,
        totalReasoningTokens: Int,
        totalTokens: Int,
        totalCostUsd: Double,
        requestCount: Int
    ) {
        self.hour = hour
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

/// One token dimension inside a single overview bucket for Swift Charts stacking.
struct BarSegment: Identifiable, Equatable {
    let id: String
    let hour: Date
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

extension OverviewBucket {
    /// Split one overview bucket into input / output / cached segments for stacked charts.
    func toBarSegments() -> [BarSegment] {
        let hourKey = Int(hour.timeIntervalSinceReferenceDate)
        return [
            BarSegment(id: "\(hourKey)|input",  hour: hour, dimension: .input,  count: totalInputTokens),
            BarSegment(id: "\(hourKey)|output", hour: hour, dimension: .output, count: totalOutputTokens),
            BarSegment(id: "\(hourKey)|cached", hour: hour, dimension: .cached, count: totalCachedTokens),
        ]
    }
}

extension Array where Element == OverviewBucket {
    /// Convert overview buckets into chart segments sorted by hour.
    func toBarSegments() -> [BarSegment] {
        self.sorted(by: { $0.hour < $1.hour })
            .flatMap { $0.toBarSegments() }
    }
}

// MARK: - Chart data cache

/// Precomputed data used by OverviewChartView's high-frequency hover path.
struct OverviewChartData: Equatable {
    let identity: OverviewChartDataIdentity
    let sortedBuckets: [OverviewBucket]
    let sortedSegments: [BarSegment]

    init(buckets: [OverviewBucket]) {
        sortedBuckets = buckets.sorted(by: { $0.hour < $1.hour })
        sortedSegments = sortedBuckets.flatMap { $0.toBarSegments() }
        identity = OverviewChartDataIdentity(buckets: sortedBuckets)
    }

    static func == (lhs: OverviewChartData, rhs: OverviewChartData) -> Bool {
        lhs.identity == rhs.identity
    }

    func nearestBucket(to date: Date, maximumDistance: TimeInterval) -> OverviewBucket? {
        guard !sortedBuckets.isEmpty else {
            return nil
        }

        var low = 0
        var high = sortedBuckets.count
        while low < high {
            let middle = (low + high) / 2
            if sortedBuckets[middle].hour < date {
                low = middle + 1
            } else {
                high = middle
            }
        }

        let candidates = [low - 1, low].compactMap { index -> OverviewBucket? in
            guard sortedBuckets.indices.contains(index) else {
                return nil
            }
            return sortedBuckets[index]
        }

        guard let nearest = candidates.min(by: {
            abs($0.hour.timeIntervalSince(date)) < abs($1.hour.timeIntervalSince(date))
        }) else {
            return nil
        }

        return abs(nearest.hour.timeIntervalSince(date)) <= maximumDistance ? nearest : nil
    }
}

struct OverviewChartDataIdentity: Equatable {
    let bucketCount: Int
    let firstHour: Date?
    let lastHour: Date?
    let valueHash: Int

    init(buckets: [OverviewBucket]) {
        bucketCount = buckets.count
        firstHour = buckets.first?.hour
        lastHour = buckets.last?.hour

        var hasher = Hasher()
        for bucket in buckets {
            hasher.combine(bucket.hour)
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
