import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.menuUsages.isEmpty {
                Text("No usage recorded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(appState.menuUsages) { usage in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayLabel(for: usage))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 8) {
                            Text("in \(formatTokens(usage.inputTokens))  out \(formatTokens(usage.outputTokens))  cache \(formatTokens(usage.cacheTokens))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            Text(formatCost(usage.costUsd))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Divider()

            VStack(spacing: 0) {
                MenuActionRow(title: "Settings", shortcut: "⌘,") {
                    globalAppDelegate?.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)

                MenuActionRow(title: "Quit", shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(10)
        .frame(width: 300)
    }

    private func displayLabel(for usage: MenuUsage) -> String {
        "\(usage.agenticTool) · \(usage.providerId) · \(usage.model)"
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
}

private struct MenuActionRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 0)
                Text(shortcut)
                    .foregroundColor(isHovered ? Color.white.opacity(0.9) : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor : .clear)
            )
            .foregroundColor(isHovered ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
