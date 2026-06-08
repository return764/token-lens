import XCTest
@testable import TokenLensApp
import GRDB

final class DatabaseManagerTests: XCTestCase {

    func test_databaseManager_createsTokenUsagesTable_onInit() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let tables = try dbManager.fetchTableNames()

        XCTAssertTrue(tables.contains("token_usages"), "token_usages table should exist")
        XCTAssertFalse(tables.contains("model_calls"), "model_calls should be gone")
        XCTAssertFalse(tables.contains("daily_usage"), "daily_usage should be gone")
        XCTAssertTrue(tables.contains("settings"))
        XCTAssertTrue(tables.contains("models"))
        XCTAssertTrue(tables.contains("local_scan_sources"))
        XCTAssertTrue(tables.contains("local_scan_files"))
    }

    func test_tokenUsages_hasExpectedColumns() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let columns = try dbManager.fetchColumnNames(table: "token_usages")

        XCTAssertTrue(columns.contains("id"))
        XCTAssertTrue(columns.contains("agentic_tool"))
        XCTAssertTrue(columns.contains("provider_id"))
        XCTAssertTrue(columns.contains("model"))
        XCTAssertTrue(columns.contains("input_tokens"))
        XCTAssertTrue(columns.contains("output_tokens"))
        XCTAssertTrue(columns.contains("cached_input_tokens"))
        XCTAssertTrue(columns.contains("cache_write_tokens"))
        XCTAssertTrue(columns.contains("reasoning_tokens"))
        XCTAssertTrue(columns.contains("total_tokens"))
        XCTAssertTrue(columns.contains("cost_usd"))
        XCTAssertTrue(columns.contains("created_at"))
    }

    func test_localScanFiles_hasIncrementalColumns() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let columns = try dbManager.fetchColumnNames(table: "local_scan_files")

        XCTAssertTrue(columns.contains("read_offset"))
        XCTAssertTrue(columns.contains("file_id"))
        XCTAssertTrue(columns.contains("parse_context_json"))
        XCTAssertFalse(columns.contains("parse_context_version"))
    }

    func test_localUsageImports_tableExists() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let tables = try dbManager.fetchTableNames()
        XCTAssertTrue(tables.contains("local_usage_imports"))
        let columns = try dbManager.fetchColumnNames(table: "local_usage_imports")
        XCTAssertTrue(columns.contains("key"))
        XCTAssertTrue(columns.contains("source_tool"))
        XCTAssertTrue(columns.contains("source_file"))
        XCTAssertTrue(columns.contains("token_usage_id"))
        XCTAssertTrue(columns.contains("imported_at"))
    }

    func test_databaseManager_storesDefaultSettings() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)

        let menuBarDisplay = try dbManager.fetchSetting(key: "menu_bar_display")

        XCTAssertEqual(menuBarDisplay, "cost", "menu_bar_display should default to cost")
    }
}
