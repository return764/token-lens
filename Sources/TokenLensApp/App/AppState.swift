import Foundation

/// Shared app state injected via environment.
@MainActor
public final class AppState: ObservableObject {
    // MARK: - Time range
    public enum TimeRange: String, CaseIterable {
        case today = "Today"
        case month = "This Month"
        case all = "All"

        var startDate: Date? {
            let cal = Calendar.current
            switch self {
            case .today:
                return cal.startOfDay(for: Date())
            case .month:
                let now = Date()
                let components = cal.dateComponents([.year, .month], from: now)
                return cal.date(from: components)
            case .all:
                return nil
            }
        }
    }

    // MARK: - Display
    @Published public var menuBarDisplay: String = "cost"
    @Published public var liveDisplayMode: String = "horizontal"
    @Published public var timeRange: TimeRange = .today

    // MARK: - Live consumption (menu bar dynamic icon)
    @Published public var liveInputTokens: Int = 0
    @Published public var liveOutputTokens: Int = 0
    @Published public var liveCostUsd: Double = 0
    @Published public var isLiveConsumptionActive: Bool = false
    private var liveConsumptionResetTask: Task<Void, Never>?
    private static let liveConsumptionResetInterval: TimeInterval = 60

    // MARK: - Usage lists
    @Published public var recentUsages: [TokenUsage] = []
    @Published public var menuUsages: [MenuUsage] = []
    @Published public var localSources: [LocalScanSource] = []
    @Published public var menuTotalTokens: Int = 0
    @Published public var menuTotalCostUsd: Double = 0

    // MARK: - Overview (chart)
    @Published public var overviewBuckets: [OverviewBucket] = []
    @Published public var overviewSource: String = ""
    @Published public var overviewProvider: String = ""
    @Published public var overviewModel: String = ""
    @Published public var overviewAvailableSources: [String] = []
    @Published public var overviewAvailableProviders: [String] = []
    @Published public var overviewAvailableModels: [String] = []
    @Published public var overviewYAxis: String = "tokens"  // "tokens" or "cost"
    private static let overviewMaximumBuckets = 24

    // MARK: - Daily heatmap
    @Published public var dailyUsageBuckets: [DailyUsageBucket] = []

    // MARK: - Repos
    private let tokenUsagesRepo: TokenUsagesRepository
    private let settingsRepo: SettingsRepository
    private let localScanRepo: LocalScanRepository
    private let localSourcesService: LocalSourcesBackgroundService

    private static let displayModes = ["cost", "tokens"]
    private static let liveDisplayModes = ["horizontal", "vertical", "cost"]

    public init(dbManager: DatabaseManager, autoScanLocalRecords: Bool = true) {
        self.tokenUsagesRepo = TokenUsagesRepository(dbManager: dbManager)
        self.settingsRepo = SettingsRepository(dbManager: dbManager)
        self.localScanRepo = LocalScanRepository(dbManager: dbManager)
        self.localSourcesService = LocalSourcesBackgroundService(repository: localScanRepo)

        // Load persisted settings
        if let mode = try? settingsRepo.fetch("menu_bar_display") {
            self.menuBarDisplay = mode
        }
        if let raw = try? settingsRepo.fetch("menu_time_range"), let tr = TimeRange(rawValue: raw) {
            self.timeRange = tr
        }
        // Migrate from old key if present
        if let layout = try? settingsRepo.fetch("live_token_display_layout"), layout == "vertical" {
            self.liveDisplayMode = "vertical"
        }
        if let mode = try? settingsRepo.fetch("live_display_mode"), Self.liveDisplayModes.contains(mode) {
            self.liveDisplayMode = mode
        }

        if autoScanLocalRecords {
            localSourcesService.onRefreshNeeded = { [weak self] in
                self?.refresh()
            }
            localSourcesService.onLiveTokensImported = { [weak self] inputTokens, outputTokens, costUsd in
                guard let self else { return }
                self.handleLiveTokensImported(inputTokens: inputTokens, outputTokens: outputTokens, costUsd: costUsd)
                self.refreshOverview()
                self.refreshDailyUsageHeatmap()
            }
        }

        // Seed models pricing, then start local scanning.
        Task {
            let modelsRepo = ModelsRepository(dbManager: dbManager)
            let seeder = ModelsSeeder(
                api: ModelsDevAPIService(),
                modelsRepo: modelsRepo,
                settingsRepo: SettingsRepository(dbManager: dbManager)
            )

            do {
                try await seeder.seedIfNeeded()
            } catch {
                print("[TokenLens] Models seed failed: \(error)")
            }

            if autoScanLocalRecords {
                await localSourcesService.start()
            }

            await MainActor.run { self.refresh() }
        }
    }

    public func scanLocalRecordsNow() async {
        await localSourcesService.rescanNow()
        refresh()
    }

    // MARK: - Refresh

    public func refresh() {
        do {
            recentUsages = try tokenUsagesRepo.fetchUsages(since: timeRange.startDate)
            localSources = try localScanRepo.fetchSources()
            let totals = try tokenUsagesRepo.fetchUsageTotals(since: timeRange.startDate)
            menuUsages = try tokenUsagesRepo.fetchMenuUsages(since: timeRange.startDate)
            menuTotalTokens = totals.totalTokens
            menuTotalCostUsd = totals.costUsd
        } catch {
            print("[TokenLens] refresh error: \(error)")
        }
        refreshOverview()
        refreshDailyUsageHeatmap()
    }

    public func refreshMenuData() {
        do {
            let totals = try tokenUsagesRepo.fetchUsageTotals(since: timeRange.startDate)
            menuUsages = try tokenUsagesRepo.fetchMenuUsages(since: timeRange.startDate)
            menuTotalTokens = totals.totalTokens
            menuTotalCostUsd = totals.costUsd
        } catch {
            print("[TokenLens] refreshMenuData error: \(error)")
        }
    }

    public func setTimeRange(_ range: TimeRange) {
        timeRange = range
        try? settingsRepo.update("menu_time_range", value: range.rawValue)
        refresh()
    }

    // MARK: - Overview

    /// 全量刷新 overview 数据：可选列表 + 聚合。首次调用时自动初始化选中项。
    public func refreshOverview() {
        do {
            let bounds = overviewBounds
            overviewAvailableSources = try tokenUsagesRepo.fetchDistinctSources(since: bounds.start, before: bounds.end)

            guard !overviewAvailableSources.isEmpty else {
                clearOverviewSelection()
                return
            }

            // 自动初始化选中项（如果尚未初始化或选中的值已不在可选列表中）
            if overviewSource.isEmpty || !overviewAvailableSources.contains(overviewSource) {
                overviewSource = overviewAvailableSources[0]
            }

            overviewAvailableProviders = try tokenUsagesRepo.fetchDistinctProviders(
                for: overviewSource,
                since: bounds.start,
                before: bounds.end
            )
            if overviewProvider.isEmpty || !overviewAvailableProviders.contains(overviewProvider) {
                overviewProvider = overviewAvailableProviders.first ?? ""
            }

            guard !overviewProvider.isEmpty else {
                overviewAvailableModels = []
                overviewModel = ""
                overviewBuckets = []
                return
            }

            overviewAvailableModels = try tokenUsagesRepo.fetchDistinctModels(
                for: overviewSource,
                provider: overviewProvider,
                since: bounds.start,
                before: bounds.end
            )
            if overviewModel.isEmpty || !overviewAvailableModels.contains(overviewModel) {
                overviewModel = overviewAvailableModels.first ?? ""
            }

            guard !overviewModel.isEmpty else {
                overviewBuckets = []
                return
            }

            overviewBuckets = try tokenUsagesRepo.fetchHourlyAggregated(
                source: overviewSource,
                provider: overviewProvider,
                model: overviewModel,
                since: bounds.start,
                before: bounds.end,
                maxBuckets: Self.overviewMaximumBuckets
            )
        } catch {
            print("[TokenLens] refreshOverview error: \(error)")
        }
    }

    /// 用户选择了新的 source → 联动重置 provider 和 model。
    public func selectOverviewSource(_ source: String) {
        guard source != overviewSource else { return }
        overviewSource = source
        do {
            let bounds = overviewBounds
            overviewAvailableProviders = try tokenUsagesRepo.fetchDistinctProviders(
                for: source,
                since: bounds.start,
                before: bounds.end
            )
            overviewProvider = overviewAvailableProviders.first ?? ""

            guard !overviewProvider.isEmpty else {
                overviewAvailableModels = []
                overviewModel = ""
                overviewBuckets = []
                return
            }

            overviewAvailableModels = try tokenUsagesRepo.fetchDistinctModels(
                for: source,
                provider: overviewProvider,
                since: bounds.start,
                before: bounds.end
            )
            overviewModel = overviewAvailableModels.first ?? ""

            guard !overviewModel.isEmpty else {
                overviewBuckets = []
                return
            }

            overviewBuckets = try tokenUsagesRepo.fetchHourlyAggregated(
                source: source,
                provider: overviewProvider,
                model: overviewModel,
                since: bounds.start,
                before: bounds.end,
                maxBuckets: Self.overviewMaximumBuckets
            )
        } catch {
            print("[TokenLens] selectOverviewSource error: \(error)")
        }
    }

    /// 用户选择了新的 provider → 联动重置 model。
    public func selectOverviewProvider(_ provider: String) {
        guard provider != overviewProvider else { return }
        overviewProvider = provider
        do {
            let bounds = overviewBounds
            overviewAvailableModels = try tokenUsagesRepo.fetchDistinctModels(
                for: overviewSource,
                provider: provider,
                since: bounds.start,
                before: bounds.end
            )
            overviewModel = overviewAvailableModels.first ?? ""

            guard !overviewModel.isEmpty else {
                overviewBuckets = []
                return
            }

            overviewBuckets = try tokenUsagesRepo.fetchHourlyAggregated(
                source: overviewSource,
                provider: provider,
                model: overviewModel,
                since: bounds.start,
                before: bounds.end,
                maxBuckets: Self.overviewMaximumBuckets
            )
        } catch {
            print("[TokenLens] selectOverviewProvider error: \(error)")
        }
    }

    /// 用户选择了新的 model → 直接重新查询。
    public func selectOverviewModel(_ model: String) {
        guard model != overviewModel else { return }
        overviewModel = model
        do {
            let bounds = overviewBounds
            overviewBuckets = try tokenUsagesRepo.fetchHourlyAggregated(
                source: overviewSource,
                provider: overviewProvider,
                model: model,
                since: bounds.start,
                before: bounds.end,
                maxBuckets: Self.overviewMaximumBuckets
            )
        } catch {
            print("[TokenLens] selectOverviewModel error: \(error)")
        }
    }

    /// 切换 Y 轴模式。
    public func setOverviewYAxis(_ mode: String) {
        overviewYAxis = mode
    }

    private var overviewBounds: (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return (start, end)
    }

    private func clearOverviewSelection() {
        overviewSource = ""
        overviewProvider = ""
        overviewModel = ""
        overviewAvailableProviders = []
        overviewAvailableModels = []
        overviewBuckets = []
    }

    // MARK: - Daily heatmap

    public func refreshDailyUsageHeatmap() {
        do {
            let bounds = dailyUsageHeatmapBounds
            dailyUsageBuckets = try tokenUsagesRepo.fetchDailyAggregated(
                since: bounds.start,
                before: bounds.end
            )
        } catch {
            print("[TokenLens] refreshDailyUsageHeatmap error: \(error)")
        }
    }

    public var dailyUsageHeatmapBounds: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        let currentWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: today) ?? today
        let start = calendar.date(
            byAdding: .weekOfYear,
            value: -(DailyUsageHeatmapData.weekCount - 1),
            to: currentWeekStart
        ) ?? currentWeekStart
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(24 * 60 * 60)
        return (start, end)
    }

    // MARK: - Menu bar display cycling

    public func cycleMenuBarDisplay() {
        guard let idx = Self.displayModes.firstIndex(of: menuBarDisplay) else {
            setMenuBarDisplay(Self.displayModes[0])
            return
        }
        let next = (idx + 1) % Self.displayModes.count
        setMenuBarDisplay(Self.displayModes[next])
    }

    public func setMenuBarDisplay(_ mode: String) {
        guard Self.displayModes.contains(mode) else { return }
        menuBarDisplay = mode
        try? settingsRepo.update("menu_bar_display", value: mode)
    }

    public func setLiveDisplayMode(_ mode: String) {
        guard Self.liveDisplayModes.contains(mode) else { return }
        liveDisplayMode = mode
        try? settingsRepo.update("live_display_mode", value: mode)
    }

    // MARK: - Live consumption handling

    /// Called when new tokens are imported from local records.
    private func handleLiveTokensImported(inputTokens: Int, outputTokens: Int, costUsd: Double) {
        tlog("🔥 LIVE tokens: in=\(inputTokens) out=\(outputTokens) cost=\(costUsd)")
        // Accumulate: multiple batches may arrive in quick succession
        liveInputTokens += inputTokens
        liveOutputTokens += outputTokens
        liveCostUsd += costUsd
        isLiveConsumptionActive = true
        tlog("🔥 LIVE active, in=\(liveInputTokens) out=\(liveOutputTokens) cost=\(liveCostUsd)")

        // Reset (cancel previous, start new) the 60-second timer
        liveConsumptionResetTask?.cancel()
        let interval = Self.liveConsumptionResetInterval
        liveConsumptionResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                tlog("🔄 LIVE reset after \(interval)s")
                self.isLiveConsumptionActive = false
                self.liveInputTokens = 0
                self.liveOutputTokens = 0
                self.liveCostUsd = 0
            }
        }
    }

    /// Human-readable text for the menu bar.
    public var menuBarDisplayText: String {
        if isLiveConsumptionActive {
            return liveDisplayString
        }
        switch menuBarDisplay {
        case "tokens":
            return formatTokens(menuTotalTokens)
        default: // "cost"
            return String(format: "$%.2f", menuTotalCostUsd)
        }
    }

    private var liveDisplayString: String {
        switch liveDisplayMode {
        case "cost":
            return String(format: "↑$%.4f", liveCostUsd)
        case "vertical":
            let input = formatTokensCompact(liveInputTokens)
            let output = formatTokensCompact(liveOutputTokens)
            return "↑\(input)\n↓\(output)"
        default: // "horizontal"
            let input = formatTokensCompact(liveInputTokens)
            let output = formatTokensCompact(liveOutputTokens)
            return "↑\(input) ↓\(output)"
        }
    }

    // MARK: - Private formatting

    /// Compact token formatting for menu bar (narrower than formatTokens).
    private func formatTokensCompact(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        } else if count > 0 {
            return "\(count)"
        } else {
            return "0"
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}
