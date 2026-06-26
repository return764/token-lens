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

// MARK: - Daily Usage Heatmap

/// Single local-day usage aggregate for the Dashboard heatmap.
public struct DailyUsageBucket: Identifiable, Equatable {
    public let day: Date
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalCachedInputTokens: Int
    public let totalCacheWriteTokens: Int
    public let totalReasoningTokens: Int
    public let totalTokens: Int
    public let totalCostUsd: Double
    public let requestCount: Int

    public var id: Date { day }
    public var totalCachedTokens: Int { totalCachedInputTokens + totalCacheWriteTokens }

    public init(
        day: Date,
        totalInputTokens: Int,
        totalOutputTokens: Int,
        totalCachedInputTokens: Int,
        totalCacheWriteTokens: Int,
        totalReasoningTokens: Int,
        totalTokens: Int,
        totalCostUsd: Double,
        requestCount: Int
    ) {
        self.day = day
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

enum DailyUsageHeatmapIntensityBasis: Equatable {
    case cost
    case tokens
    case none
}

struct DailyUsageHeatmapCell: Identifiable, Equatable {
    let date: Date
    let weekIndex: Int
    let weekdayIndex: Int
    let bucket: DailyUsageBucket
    let intensityLevel: Int
    let isFuture: Bool

    var id: Date { date }
    var hasUsage: Bool { bucket.requestCount > 0 }
}

struct DailyUsageHeatmapMonthLabel: Identifiable, Equatable {
    let title: String
    let weekIndex: Int

    var id: String { "\(title)-\(weekIndex)" }
}

struct DailyUsageHeatmapData: Equatable {
    static let weekCount = 53
    static let daysPerWeek = 7
    static let cellCount = weekCount * daysPerWeek

    let cells: [DailyUsageHeatmapCell]
    let monthLabels: [DailyUsageHeatmapMonthLabel]
    let intensityBasis: DailyUsageHeatmapIntensityBasis
    let startDate: Date
    let endDate: Date

    init(
        buckets: [DailyUsageBucket],
        endDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        let endDay = calendar.startOfDay(for: endDate)
        let endWeekStart = Self.startOfWeek(containing: endDay, calendar: calendar)
        let startDay = calendar.date(byAdding: .weekOfYear, value: -(Self.weekCount - 1), to: endWeekStart) ?? endWeekStart
        let bucketByDay = Dictionary(uniqueKeysWithValues: buckets.map { bucket in
            (calendar.startOfDay(for: bucket.day), bucket)
        })
        let basis = Self.intensityBasis(for: Array(bucketByDay.values))

        self.startDate = startDay
        self.endDate = endDay
        self.intensityBasis = basis

        let maxCost = bucketByDay.values.map(\.totalCostUsd).max() ?? 0
        let maxTokens = bucketByDay.values.map(\.totalTokens).max() ?? 0

        self.cells = (0..<Self.cellCount).compactMap { offset -> DailyUsageHeatmapCell? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }

            let day = calendar.startOfDay(for: date)
            let emptyBucket = DailyUsageBucket(
                day: day,
                totalInputTokens: 0,
                totalOutputTokens: 0,
                totalCachedInputTokens: 0,
                totalCacheWriteTokens: 0,
                totalReasoningTokens: 0,
                totalTokens: 0,
                totalCostUsd: 0,
                requestCount: 0
            )
            let bucket = bucketByDay[day] ?? emptyBucket
            return DailyUsageHeatmapCell(
                date: day,
                weekIndex: offset / Self.daysPerWeek,
                weekdayIndex: offset % Self.daysPerWeek,
                bucket: bucket,
                intensityLevel: Self.intensityLevel(for: bucket, basis: basis, maxCost: maxCost, maxTokens: maxTokens),
                isFuture: day > endDay
            )
        }

        self.monthLabels = Self.makeMonthLabels(cells: cells, calendar: calendar)
    }

    func cell(on date: Date, calendar: Calendar = .current) -> DailyUsageHeatmapCell? {
        let day = calendar.startOfDay(for: date)
        return cells.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + daysPerWeek) % daysPerWeek
        return calendar.date(byAdding: .day, value: -daysFromWeekStart, to: date) ?? date
    }

    private static func intensityBasis(for buckets: [DailyUsageBucket]) -> DailyUsageHeatmapIntensityBasis {
        if buckets.contains(where: { $0.totalCostUsd > 0 }) {
            return .cost
        }
        if buckets.contains(where: { $0.totalTokens > 0 }) {
            return .tokens
        }
        return .none
    }

    private static func intensityLevel(
        for bucket: DailyUsageBucket,
        basis: DailyUsageHeatmapIntensityBasis,
        maxCost: Double,
        maxTokens: Int
    ) -> Int {
        switch basis {
        case .cost:
            guard bucket.totalCostUsd > 0, maxCost > 0 else { return 0 }
            return scaledLevel(value: bucket.totalCostUsd, maxValue: maxCost)
        case .tokens:
            guard bucket.totalTokens > 0, maxTokens > 0 else { return 0 }
            return scaledLevel(value: Double(bucket.totalTokens), maxValue: Double(maxTokens))
        case .none:
            return 0
        }
    }

    private static func scaledLevel(value: Double, maxValue: Double) -> Int {
        let ratio = min(max(value / maxValue, 0), 1)
        return max(1, min(4, Int(ceil(ratio * 4))))
    }

    private static func makeMonthLabels(
        cells: [DailyUsageHeatmapCell],
        calendar: Calendar
    ) -> [DailyUsageHeatmapMonthLabel] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM"

        var labels: [DailyUsageHeatmapMonthLabel] = []
        var seenMonths = Set<String>()

        for cell in cells {
            let components = calendar.dateComponents([.year, .month, .day], from: cell.date)
            guard let year = components.year, let month = components.month else {
                continue
            }
            let key = "\(year)-\(month)"
            let isFirstVisibleDayOfMonth = components.day == 1 || labels.isEmpty
            guard isFirstVisibleDayOfMonth, !seenMonths.contains(key) else {
                continue
            }

            seenMonths.insert(key)
            labels.append(DailyUsageHeatmapMonthLabel(
                title: formatter.string(from: cell.date),
                weekIndex: cell.weekIndex
            ))
        }

        return labels
    }
}
