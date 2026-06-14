import SwiftUI

struct SettingsTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            overviewSection
            usageSection
            localSourcesSection
            monitoringSection
        }
        .formStyle(.grouped)
        .onAppear { appState.refresh() }
    }

    private var overviewSection: some View {
        Section("Overview") {
            if appState.overviewAvailableSources.isEmpty {
                Text("No token usage recorded yet.")
                    .foregroundColor(.secondary)
            } else {
                // Filter bar
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

                // Chart
                OverviewChartView(
                    buckets: appState.overviewBuckets,
                    yAxisMode: appState.overviewYAxis
                )

                // Legend (only in tokens mode)
                if appState.overviewYAxis == "tokens" {
                    HStack {
                        Spacer()
                        OverviewLegend()
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var usageSection: some View {
        Section("Recent Usage") {
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
    }

    private var localSourcesSection: some View {
        Section("Local Sources") {
            if appState.localSources.isEmpty {
                Text("No local source scan status yet.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(appState.localSources) { source in
                    VStack(alignment: .leading, spacing: 2) {
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
                        if let finishedAt = source.lastScanFinishedAt {
                            Text("Last scan: \(finishedAt, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            HStack {
                Button("Rescan Now") {
                    Task { await appState.scanLocalRecordsNow() }
                }
            }
        }
    }

    private var monitoringSection: some View {
        Section("Monitoring") {
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
