import XCTest
@testable import TokenLensApp

final class DailyUsageHeatmapDataTests: XCTestCase {
    func test_heatmapData_buildsTrailing53WeekGridIncludingToday() throws {
        let calendar = Calendar.current
        let today = try requireLocalDate(year: 2026, month: 6, day: 17)

        let data = DailyUsageHeatmapData(buckets: [], endDate: today, calendar: calendar)

        XCTAssertEqual(data.cells.count, DailyUsageHeatmapData.cellCount)
        XCTAssertEqual(data.cells.first?.weekIndex, 0)
        XCTAssertEqual(data.cells.last?.weekIndex, DailyUsageHeatmapData.weekCount - 1)
        XCTAssertNotNil(data.cell(on: today, calendar: calendar))
        XCTAssertTrue(data.cells.allSatisfy { $0.intensityLevel == 0 })
        XCTAssertEqual(data.intensityBasis, .none)
        XCTAssertFalse(data.monthLabels.isEmpty)
    }

    func test_heatmapData_usesCostLevelsWhenAnyCostExists() throws {
        let calendar = Calendar.current
        let today = try requireLocalDate(year: 2026, month: 6, day: 17)
        let lowDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))
        let highDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))

        let data = DailyUsageHeatmapData(
            buckets: [
                makeBucket(day: lowDay, tokens: 100, cost: 1),
                makeBucket(day: highDay, tokens: 10, cost: 4),
            ],
            endDate: today,
            calendar: calendar
        )

        XCTAssertEqual(data.intensityBasis, .cost)
        XCTAssertEqual(data.cell(on: lowDay, calendar: calendar)?.intensityLevel, 1)
        XCTAssertEqual(data.cell(on: highDay, calendar: calendar)?.intensityLevel, 4)
    }

    func test_heatmapData_fallsBackToTokenLevelsWhenCostsAreZero() throws {
        let calendar = Calendar.current
        let today = try requireLocalDate(year: 2026, month: 6, day: 17)
        let lowDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))
        let highDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))

        let data = DailyUsageHeatmapData(
            buckets: [
                makeBucket(day: lowDay, tokens: 100, cost: 0),
                makeBucket(day: highDay, tokens: 400, cost: 0),
            ],
            endDate: today,
            calendar: calendar
        )

        XCTAssertEqual(data.intensityBasis, .tokens)
        XCTAssertEqual(data.cell(on: lowDay, calendar: calendar)?.intensityLevel, 1)
        XCTAssertEqual(data.cell(on: highDay, calendar: calendar)?.intensityLevel, 4)
    }

    func test_heatmapData_keepsZeroUsageDaysVisibleAndSorted() throws {
        let calendar = Calendar.current
        let today = try requireLocalDate(year: 2026, month: 6, day: 17)
        let usageDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: today))
        let zeroDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: today))

        let data = DailyUsageHeatmapData(
            buckets: [makeBucket(day: usageDay, tokens: 200, cost: 0.25)],
            endDate: today,
            calendar: calendar
        )

        XCTAssertEqual(data.cell(on: usageDay, calendar: calendar)?.bucket.requestCount, 1)
        XCTAssertEqual(data.cell(on: zeroDay, calendar: calendar)?.bucket.requestCount, 0)
        XCTAssertEqual(data.cell(on: zeroDay, calendar: calendar)?.intensityLevel, 0)
        XCTAssertEqual(data.cells, data.cells.sorted(by: { $0.date < $1.date }))
    }

    private func makeBucket(day: Date, tokens: Int, cost: Double) -> DailyUsageBucket {
        DailyUsageBucket(
            day: Calendar.current.startOfDay(for: day),
            totalInputTokens: tokens / 2,
            totalOutputTokens: tokens / 2,
            totalCachedInputTokens: 0,
            totalCacheWriteTokens: 0,
            totalReasoningTokens: 0,
            totalTokens: tokens,
            totalCostUsd: cost,
            requestCount: tokens > 0 ? 1 : 0
        )
    }

    private func requireLocalDate(year: Int, month: Int, day: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(year: year, month: month, day: day)))
    }
}
