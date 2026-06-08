import XCTest
@testable import TokenLensApp

final class AppStateTests: XCTestCase {

    @MainActor
    private func setupState(withData: Bool = true) throws -> AppState {
        let dbManager = try DatabaseManager(kind: .inMemory)
        if withData {
            let repo = TokenUsagesRepository(dbManager: dbManager)
            let now = Date()
            try repo.insert(TokenUsage(
                id: "u-1", agenticTool: "pi", providerId: "anthropic",
                model: "claude-sonnet-4-20250514",
                inputTokens: 100, outputTokens: 50, cachedInputTokens: 0,
                cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 150,
                costUsd: 0.003, createdAt: now
            ))
            try repo.insert(TokenUsage(
                id: "u-2", agenticTool: "codex", providerId: "openai",
                model: "gpt-4.1-mini",
                inputTokens: 200, outputTokens: 100, cachedInputTokens: 10,
                cacheWriteTokens: 5, reasoningTokens: 0, totalTokens: 315,
                costUsd: 0.0008, createdAt: now
            ))
        }
        return AppState(dbManager: dbManager, autoScanLocalRecords: false)
    }

    @MainActor
    func test_appState_refresh_populatesRecentUsages() throws {
        let state = try setupState()
        state.refresh()

        XCTAssertEqual(state.recentUsages.count, 2)
        XCTAssertEqual(state.recentUsages[0].id, "u-2") // most recent first
    }

    @MainActor
    func test_appState_emptyDatabase_showsEmptyUsages() throws {
        let state = try setupState(withData: false)
        state.refresh()

        XCTAssertEqual(state.recentUsages.count, 0)
    }

    @MainActor
    func test_appState_menuBarDisplay_defaultsToCost() throws {
        let state = try setupState(withData: false)
        XCTAssertEqual(state.menuBarDisplay, "cost")
    }

    @MainActor
    func test_appState_cycleMenuBarDisplay() throws {
        let state = try setupState(withData: false)

        state.cycleMenuBarDisplay()
        XCTAssertEqual(state.menuBarDisplay, "tokens")

        state.cycleMenuBarDisplay()
        XCTAssertEqual(state.menuBarDisplay, "cost")
    }

    @MainActor
    func test_appState_menuBarDisplay_persistsToSettings() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let state = AppState(dbManager: dbManager, autoScanLocalRecords: false)
        let settingsRepo = SettingsRepository(dbManager: dbManager)

        state.setMenuBarDisplay("tokens")

        let saved = try settingsRepo.fetch("menu_bar_display")
        XCTAssertEqual(saved, "tokens")
    }

    @MainActor
    func test_appState_menuBarText_returnsCorrectValue() throws {
        let state = try setupState()
        state.refresh()

        state.menuBarDisplay = "cost"
        XCTAssertTrue(state.menuBarDisplayText.hasPrefix("$"))

        state.menuBarDisplay = "tokens"
        XCTAssertFalse(state.menuBarDisplayText.hasPrefix("$"))
    }
}
