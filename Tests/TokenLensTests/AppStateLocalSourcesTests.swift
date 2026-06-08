import XCTest
@testable import TokenLensApp

final class AppStateLocalSourcesTests: XCTestCase {
    @MainActor
    func test_refresh_populatesLocalSources() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let localRepo = LocalScanRepository(dbManager: dbManager)
        try localRepo.upsertSourceStatus(LocalScanSourceStatus(
            sourceTool: "pi", displayName: "pi", rootPath: "/tmp/pi", status: "ok",
            lastScanStartedAt: Date(), lastScanFinishedAt: Date(), filesSeen: 1,
            filesScanned: 1, eventsImported: 1, parseErrorCount: 0, lastError: nil
        ))
        let state = AppState(dbManager: dbManager, autoScanLocalRecords: false)

        state.refresh()

        XCTAssertEqual(state.localSources.count, 1)
        XCTAssertEqual(state.localSources[0].sourceTool, "pi")
        XCTAssertEqual(state.localSources[0].status, "ok")
    }
}
