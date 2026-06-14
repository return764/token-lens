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
    @Published public var localSources: [LocalScanSource] = []

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
                self?.handleLiveTokensImported(inputTokens: inputTokens, outputTokens: outputTokens, costUsd: costUsd)
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
        } catch {
            print("[TokenLens] refresh error: \(error)")
        }
    }

    public func setTimeRange(_ range: TimeRange) {
        timeRange = range
        try? settingsRepo.update("menu_time_range", value: range.rawValue)
        refresh()
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
            let totalTokens = recentUsages.reduce(0) { $0 + $1.totalTokens }
            return formatTokens(totalTokens)
        default: // "cost"
            let totalCost = recentUsages.reduce(0.0) { $0 + $1.costUsd }
            return String(format: "$%.2f", totalCost)
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
