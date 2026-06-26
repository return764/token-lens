import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case dashboard
    case usage
    case sources
    case settings

    static let defaultSelection: DashboardPage = .dashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .usage: return "Usage"
        case .sources: return "Sources"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .usage: return "list.bullet.rectangle"
        case .sources: return "externaldrive.connected.to.line.below"
        case .settings: return "gearshape"
        }
    }

    var isDetailPage: Bool {
        self != .dashboard
    }

    var showsDailyUsageHeatmap: Bool {
        self == .dashboard
    }
}

struct SettingsTab: View {
    @ObservedObject var appState: AppState
    @State private var selectedPage: DashboardPage = .defaultSelection

    var body: some View {
        VStack(spacing: 12) {
            dashboardTabBar
            selectedPageView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { appState.refresh() }
    }

    private var dashboardTabBar: some View {
        HStack(spacing: 24) {
            ForEach(DashboardPage.allCases) { page in
                Button {
                    selectedPage = page
                } label: {
                    VStack(spacing: 4) {
                        Text(page.title)
                            .font(.title3)
                            .fontWeight(selectedPage == page ? .semibold : .regular)
                            .foregroundColor(.primary)
                        Rectangle()
                            .fill(selectedPage == page ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var selectedPageView: some View {
        switch selectedPage {
        case .dashboard:
            dashboardPage
        case .usage:
            usagePage
        case .sources:
            sourcesPage
        case .settings:
            settingsPage
        }
    }

    private var dashboardPage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 18) {
                dashboardSummary
                Divider()
                DailyUsageHeatmapView(buckets: appState.dailyUsageBuckets)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Overview")
                        .font(.headline)
                    overviewContent
                }
            }
        }
    }

    private func pageScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 8)
        }
    }

    private var dashboardSummary: some View {
        HStack(spacing: 16) {
            summaryMetric("Cost", value: formatCost(appState.menuTotalCostUsd))
            Divider()
            summaryMetric("Tokens", value: formatTokens(appState.menuTotalTokens))
            Divider()
            summaryMetric("Events", value: "\(appState.recentUsages.count)")
            Divider()
            summaryMetric("Range", value: appState.timeRange.rawValue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func summaryMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var overviewContent: some View {
        if appState.overviewAvailableSources.isEmpty {
            Text("No token usage recorded yet.")
                .foregroundColor(.secondary)
        } else {
            overviewFilters

            OverviewChartView(
                buckets: appState.overviewBuckets,
                yAxisMode: appState.overviewYAxis
            )

            HStack {
                Spacer()
                OverviewLegend()
                    .opacity(appState.overviewYAxis == "tokens" ? 1 : 0)
                Spacer()
            }
            .frame(height: 18)
            .padding(.top, 4)
            .accessibilityHidden(appState.overviewYAxis != "tokens")
        }
    }

    private var overviewFilters: some View {
        HStack(spacing: 12) {
            Picker("Source", selection: Binding(
                get: { appState.overviewSource },
                set: { appState.selectOverviewSource($0) }
            )) {
                ForEach(appState.overviewAvailableSources, id: \.self) { source in
                    Text(overviewSourceDisplayName(source)).tag(source)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("Provider", selection: Binding(
                get: { appState.overviewProvider },
                set: { appState.selectOverviewProvider($0) }
            )) {
                ForEach(appState.overviewAvailableProviders, id: \.self) { provider in
                    Text(provider).tag(provider)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .disabled(appState.overviewAvailableProviders.isEmpty)

            Picker("Model", selection: Binding(
                get: { appState.overviewModel },
                set: { appState.selectOverviewModel($0) }
            )) {
                ForEach(appState.overviewAvailableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            .disabled(appState.overviewAvailableModels.isEmpty)

            Spacer()

            Picker("Y Axis", selection: Binding(
                get: { appState.overviewYAxis },
                set: { appState.setOverviewYAxis($0) }
            )) {
                Text("Tokens").tag("tokens")
                Text("Cost").tag("cost")
            }
            .labelsHidden()
            .frame(width: 100)
        }
        .padding(.bottom, 4)
    }

    private var usagePage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Usage")
                    .font(.headline)
                usageRows
            }
        }
    }

    @ViewBuilder
    private var usageRows: some View {
        if appState.recentUsages.isEmpty {
            Text("No token usage recorded yet.")
                .foregroundColor(.secondary)
        } else {
            ForEach(appState.recentUsages.prefix(5)) { usage in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(usage.agenticTool) · \(usage.providerId)")
                            .fontWeight(.medium)
                        Spacer()
                        Text(formatCost(usage.costUsd))
                            .monospacedDigit()
                    }
                    HStack {
                        if let model = usage.model {
                            Text(model)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("in \(formatTokens(usage.inputTokens)) / out \(formatTokens(usage.outputTokens))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if usage.cachedInputTokens > 0 || usage.cacheWriteTokens > 0 || usage.reasoningTokens > 0 {
                        HStack(spacing: 8) {
                            if usage.cachedInputTokens > 0 {
                                Text("cache↩ \(formatTokens(usage.cachedInputTokens))")
                            }
                            if usage.cacheWriteTokens > 0 {
                                Text("cache↪ \(formatTokens(usage.cacheWriteTokens))")
                            }
                            if usage.reasoningTokens > 0 {
                                Text("think \(formatTokens(usage.reasoningTokens))")
                            }
                            Spacer()
                            Text("total \(formatTokens(usage.totalTokens))")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var sourcesPage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Sources")
                        .font(.headline)
                    Spacer()
                    Button("Rescan Now") {
                        Task { await appState.scanLocalRecordsNow() }
                    }
                }
                sourcesRows
            }
        }
    }

    @ViewBuilder
    private var sourcesRows: some View {
        if appState.localSources.isEmpty {
            Text("No local source scan status yet.")
                .foregroundColor(.secondary)
        } else {
            ForEach(appState.localSources) { source in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Circle()
                            .fill(sourceStatusColor(source.status))
                            .frame(width: 8, height: 8)
                        Text(localSourceDisplayName(source.sourceTool))
                            .fontWeight(.medium)
                        Spacer()
                        Text(source.status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(source.rootPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 10) {
                        Text("events \(formatTokens(source.eventsImported))")
                        Text("errors \(formatTokens(source.parseErrorCount))")
                        if let finishedAt = source.lastScanFinishedAt {
                            Text("last scan \(finishedAt, style: .relative) ago")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    if let lastError = source.lastError, !lastError.isEmpty {
                        Text(lastError)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var settingsPage: some View {
        pageScroll {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings")
                    .font(.headline)

                Picker("Menu Bar Display", selection: $appState.menuBarDisplay) {
                    Text("Cost").tag("cost")
                    Text("Tokens").tag("tokens")
                }
                .onChange(of: appState.menuBarDisplay) { _, newValue in
                    appState.setMenuBarDisplay(newValue)
                }

                Picker("Live Usage Mode", selection: $appState.liveDisplayMode) {
                    Text("Token (→)").tag("horizontal")
                    Text("Token (↓)").tag("vertical")
                    Text("Cost ($)").tag("cost")
                }
                .onChange(of: appState.liveDisplayMode) { _, newValue in
                    appState.setLiveDisplayMode(newValue)
                }
                Text("How live import activity is shown in the menu bar.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Aggregation Range", selection: Binding(
                    get: { appState.timeRange },
                    set: { appState.setTimeRange($0) }
                )) {
                    ForEach(AppState.TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
            }
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

    private func formatCost(_ cost: Double) -> String {
        String(format: "$%.4f", cost)
    }

    private func localSourceDisplayName(_ sourceTool: String) -> String {
        switch sourceTool {
        case "claude_code": return "Claude Code"
        case "codex": return "Codex"
        case "pi": return "pi"
        default: return sourceTool
        }
    }

    private func overviewSourceDisplayName(_ sourceTool: String) -> String {
        switch sourceTool {
        case "claude_code": return "Claude Code"
        case "codex": return "Codex"
        case "pi": return "pi"
        default: return sourceTool
        }
    }

    private func sourceStatusColor(_ status: String) -> Color {
        switch status {
        case "watching": return .green
        case "ok": return .green
        case "scanning": return .blue
        case "not_found": return .gray
        case "permission_denied": return .orange
        case "parse_error": return .red
        default: return .secondary
        }
    }
}
