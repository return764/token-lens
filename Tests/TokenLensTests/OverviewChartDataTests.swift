import XCTest
@testable import TokenLensApp

final class OverviewChartDataTests: XCTestCase {
    func test_overviewChartData_sortsBucketsAndBuildsSegmentsOnce() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let buckets = [
            makeBucket(minute: base.addingTimeInterval(120), input: 3, output: 4, cached: 5),
            makeBucket(minute: base, input: 1, output: 2, cached: 0),
            makeBucket(minute: base.addingTimeInterval(60), input: 2, output: 3, cached: 1),
        ]

        let data = OverviewChartData(buckets: buckets)

        XCTAssertEqual(data.sortedBuckets.map(\.minute), [
            base,
            base.addingTimeInterval(60),
            base.addingTimeInterval(120),
        ])
        XCTAssertEqual(data.sortedSegments.count, 9)
        XCTAssertEqual(data.sortedSegments.prefix(3).map(\.dimension), [.input, .output, .cached])
    }

    func test_nearestBucket_usesMaximumDistance() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let data = OverviewChartData(buckets: [
            makeBucket(minute: base, input: 1),
            makeBucket(minute: base.addingTimeInterval(60), input: 2),
        ])

        XCTAssertEqual(
            data.nearestBucket(to: base.addingTimeInterval(29), maximumDistance: 30)?.minute,
            base
        )
        XCTAssertNil(data.nearestBucket(to: base.addingTimeInterval(91), maximumDistance: 30))
    }

    func test_nearestBucket_remainsFastAcrossFullDayBuckets() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let buckets = (0..<1_440).reversed().map { index in
            makeBucket(minute: base.addingTimeInterval(TimeInterval(index * 60)), input: index)
        }
        let data = OverviewChartData(buckets: buckets)
        let dates = (0..<5_000).map { index in
            base.addingTimeInterval(TimeInterval((index % 1_440) * 60) + 3)
        }

        let start = CFAbsoluteTimeGetCurrent()
        var found = 0
        for date in dates {
            if data.nearestBucket(to: date, maximumDistance: 30) != nil {
                found += 1
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(found, dates.count)
        XCTAssertLessThan(elapsed, 1.0)
    }

    private func makeBucket(
        minute: Date,
        input: Int = 0,
        output: Int = 0,
        cached: Int = 0
    ) -> MinuteAggregation {
        MinuteAggregation(
            minute: minute,
            totalInputTokens: input,
            totalOutputTokens: output,
            totalCachedInputTokens: cached,
            totalCacheWriteTokens: 0,
            totalReasoningTokens: 0,
            totalTokens: input + output + cached,
            totalCostUsd: 0,
            requestCount: 1
        )
    }
}
