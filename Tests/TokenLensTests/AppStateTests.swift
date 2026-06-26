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

    @MainActor
    func test_appState_refreshMenuData_populatesMenuTotalsAndRows() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = TokenUsagesRepository(dbManager: dbManager)
        let now = Date()

        try repo.insert(TokenUsage(
            id: "u-1", agenticTool: "pi", providerId: "anthropic",
            model: nil,
            inputTokens: 100, outputTokens: 50, cachedInputTokens: 0,
            cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 150,
            costUsd: 0.003, createdAt: now
        ))

        let state = AppState(dbManager: dbManager, autoScanLocalRecords: false)
        state.refreshMenuData()

        XCTAssertEqual(state.menuTotalTokens, 150)
        XCTAssertEqual(state.menuTotalCostUsd, 0.003, accuracy: 0.00001)
        XCTAssertEqual(state.menuUsages.count, 1)
        XCTAssertEqual(state.menuUsages[0].id, "pi::anthropic::unknown")
    }

    @MainActor
    func test_appState_refreshOverview_staysOnTodayWhenTimeRangeIsAll() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = TokenUsagesRepository(dbManager: dbManager)
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: todayStart))

        try repo.insert(TokenUsage(
            id: "old-1", agenticTool: "pi", providerId: "anthropic",
            model: "claude-sonnet-4-20250514",
            inputTokens: 100, outputTokens: 50, cachedInputTokens: 0,
            cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 150,
            costUsd: 0.003, createdAt: todayStart.addingTimeInterval(-2 * 24 * 60 * 60)
        ))
        try repo.insert(TokenUsage(
            id: "new-1", agenticTool: "codex", providerId: "openai",
            model: "gpt-5",
            inputTokens: 200, outputTokens: 100, cachedInputTokens: 10,
            cacheWriteTokens: 5, reasoningTokens: 0, totalTokens: 315,
            costUsd: 0.0008, createdAt: now
        ))
        try repo.insert(TokenUsage(
            id: "future-1", agenticTool: "claude-code", providerId: "anthropic",
            model: "claude-sonnet-4-20250514",
            inputTokens: 300, outputTokens: 100, cachedInputTokens: 0,
            cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 400,
            costUsd: 0.004, createdAt: tomorrowStart
        ))

        let state = AppState(dbManager: dbManager, autoScanLocalRecords: false)
        state.setTimeRange(.all)

        XCTAssertEqual(state.recentUsages.count, 3)
        XCTAssertEqual(state.menuTotalTokens, 865)
        XCTAssertEqual(state.overviewAvailableSources, ["codex"])
        XCTAssertEqual(state.overviewSource, "codex")
        XCTAssertEqual(state.overviewProvider, "openai")
        XCTAssertEqual(state.overviewModel, "gpt-5")
        XCTAssertEqual(state.overviewBuckets.count, 1)
    }

    @MainActor
    func test_appState_dailyHeatmapRefreshesIndependentlyFromTimeRange() throws {
        let dbManager = try DatabaseManager(kind: .inMemory)
        let repo = TokenUsagesRepository(dbManager: dbManager)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: todayStart))

        try repo.insert(TokenUsage(
            id: "yesterday-1", agenticTool: "pi", providerId: "anthropic",
            model: "claude-sonnet-4-20250514",
            inputTokens: 100, outputTokens: 50, cachedInputTokens: 0,
            cacheWriteTokens: 0, reasoningTokens: 0, totalTokens: 150,
            costUsd: 0.003, createdAt: yesterday.addingTimeInterval(60 * 60)
        ))
        try repo.insert(TokenUsage(
            id: "today-1", agenticTool: "codex", providerId: "openai",
            model: "gpt-5",
            inputTokens: 200, outputTokens: 100, cachedInputTokens: 10,
            cacheWriteTokens: 5, reasoningTokens: 0, totalTokens: 315,
            costUsd: 0.0008, createdAt: todayStart.addingTimeInterval(2 * 60 * 60)
        ))

        let state = AppState(dbManager: dbManager, autoScanLocalRecords: false)
        state.setTimeRange(.today)

        XCTAssertEqual(state.menuTotalTokens, 315)
        XCTAssertEqual(state.dailyUsageBuckets.count, 2)

        state.setTimeRange(.all)

        XCTAssertEqual(state.menuTotalTokens, 465)
        XCTAssertEqual(state.dailyUsageBuckets.count, 2)
        XCTAssertEqual(state.dailyUsageBuckets.map(\.totalTokens).reduce(0, +), 465)
    }
}
