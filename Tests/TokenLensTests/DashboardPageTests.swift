import XCTest
@testable import TokenLensApp

final class DashboardPageTests: XCTestCase {
    func test_dashboardPage_defaultSelection_isDashboard() {
        XCTAssertEqual(DashboardPage.defaultSelection, .dashboard)
    }

    func test_dashboardPage_groupsTaskOrientedDestinations() {
        XCTAssertEqual(DashboardPage.allCases, [.dashboard, .usage, .sources, .settings])
        XCTAssertFalse(DashboardPage.dashboard.isDetailPage)
        XCTAssertTrue(DashboardPage.usage.isDetailPage)
        XCTAssertTrue(DashboardPage.sources.isDetailPage)
        XCTAssertTrue(DashboardPage.settings.isDetailPage)
    }

    func test_dashboardPage_ownsDailyUsageHeatmap() {
        XCTAssertTrue(DashboardPage.dashboard.showsDailyUsageHeatmap)
        XCTAssertFalse(DashboardPage.usage.showsDailyUsageHeatmap)
        XCTAssertFalse(DashboardPage.sources.showsDailyUsageHeatmap)
        XCTAssertFalse(DashboardPage.settings.showsDailyUsageHeatmap)
    }
}
