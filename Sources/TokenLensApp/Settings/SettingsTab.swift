import SwiftUI

struct SettingsTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            usageSection
            localSourcesSection
            monitoringSection
        }
        .formStyle(.grouped)
        .onAppear { appState.refresh() }
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

            Picker("Live Token Layout", selection: $appState.liveTokenDisplayLayout) {
                Text("Horizontal").tag("horizontal")
                Text("Vertical").tag("vertical")
            }
            .onChange(of: appState.liveTokenDisplayLayout) { _, newValue in
                appState.setLiveTokenDisplayLayout(newValue)
            }
            Text("Controls how active live input/output tokens are shown in the menu bar.")
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
