import XCTest
@testable import TokenLensApp

final class SettingsRepositoryTests: XCTestCase {

    var dbManager: DatabaseManager!

    override func setUp() {
        super.setUp()
        dbManager = try! DatabaseManager(kind: .inMemory)
    }

    func test_fetchSetting_returnsDefaultValues() throws {
        let repo = SettingsRepository(dbManager: dbManager)

        let menuBar = try repo.fetch("menu_bar_display")

        XCTAssertEqual(menuBar, "cost")
    }

    func test_fetchSetting_returnsNil_forUnknownKey() throws {
        let repo = SettingsRepository(dbManager: dbManager)

        let value = try repo.fetch("nonexistent_key")

        XCTAssertNil(value)
    }

    func test_updateSetting_persistsValue() throws {
        let repo = SettingsRepository(dbManager: dbManager)

        try repo.update("menu_bar_display", value: "tokens")

        let updated = try repo.fetch("menu_bar_display")
        XCTAssertEqual(updated, "tokens")
    }

    func test_updateSetting_tracksUpdatedAt() throws {
        let repo = SettingsRepository(dbManager: dbManager)

        let before = Date().addingTimeInterval(-1)
        try repo.update("menu_bar_display", value: "cost")
        let after = Date().addingTimeInterval(1)

        let timestamp = try repo.fetchUpdatedAt("menu_bar_display")
        XCTAssertNotNil(timestamp)
        // updated_at should be within the [before, after] interval
        XCTAssertGreaterThanOrEqual(timestamp!, before)
        XCTAssertLessThanOrEqual(timestamp!, after)
    }
}
