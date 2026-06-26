import SwiftUI

struct DailyUsageHeatmapView: View {
    let buckets: [DailyUsageBucket]
    private let data: DailyUsageHeatmapData

    @State private var hoveredCellID: Date?
    @State private var pendingHoverCellID: Date?
    @State private var hoverActivationTask: Task<Void, Never>?

    private let cellSize: CGFloat = 10
    private let cellGap: CGFloat = 3
    private let weekdayLabelWidth: CGFloat = 28
    private let hoverActivationDelayNanoseconds: UInt64 = 150_000_000

    init(buckets: [DailyUsageBucket], endDate: Date = Date()) {
        self.buckets = buckets
        self.data = DailyUsageHeatmapData(buckets: buckets, endDate: endDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily Activity")
                    .font(.headline)
                Spacer()
                DailyUsageHeatmapLegend()
            }

            heatmapGrid
            .frame(height: gridTotalHeight)
        }
        .onDisappear {
            hoverActivationTask?.cancel()
        }
    }

    private var heatmapGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            monthLabels
                .padding(.leading, weekdayLabelWidth)

            HStack(alignment: .top, spacing: 6) {
                weekdayLabels
                    .frame(width: weekdayLabelWidth, height: gridHeight, alignment: .topTrailing)

                HStack(alignment: .top, spacing: cellGap) {
                    ForEach(0..<DailyUsageHeatmapData.weekCount, id: \.self) { weekIndex in
                        VStack(spacing: cellGap) {
                            ForEach(cells(in: weekIndex)) { cell in
                                DailyUsageHeatmapCellView(
                                    cell: cell,
                                    color: color(for: cell),
                                    size: cellSize
                                )
                                .onHover { hovering in
                                    if hovering {
                                        scheduleHover(for: cell.id)
                                    } else {
                                        cancelHover(for: cell.id)
                                    }
                                }
                                .popover(
                                    isPresented: hoverBinding(for: cell),
                                    attachmentAnchor: .rect(.bounds),
                                    arrowEdge: .top
                                ) {
                                    DailyUsageHeatmapTooltip(cell: cell)
                                        .frame(width: 230)
                                        .padding(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var monthLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(data.monthLabels) { label in
                Text(label.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .leading)
                    .offset(x: CGFloat(label.weekIndex) * (cellSize + cellGap))
            }
        }
        .frame(
            width: CGFloat(DailyUsageHeatmapData.weekCount) * cellSize + CGFloat(DailyUsageHeatmapData.weekCount - 1) * cellGap,
            height: 18,
            alignment: .topLeading
        )
    }

    private var weekdayLabels: some View {
        VStack(spacing: cellGap) {
            ForEach(0..<DailyUsageHeatmapData.daysPerWeek, id: \.self) { index in
                Text(weekdayLabel(for: index))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: cellSize, alignment: .center)
                    .opacity(showWeekdayLabel(for: index) ? 1 : 0)
            }
        }
    }

    private var gridHeight: CGFloat {
        CGFloat(DailyUsageHeatmapData.daysPerWeek) * cellSize + CGFloat(DailyUsageHeatmapData.daysPerWeek - 1) * cellGap
    }

    private var gridTotalHeight: CGFloat {
        18 + 4 + gridHeight + 2
    }

    private func cells(in weekIndex: Int) -> [DailyUsageHeatmapCell] {
        data.cells.filter { $0.weekIndex == weekIndex }
    }

    private func color(for cell: DailyUsageHeatmapCell) -> Color {
        guard !cell.isFuture else {
            return Color(nsColor: .separatorColor).opacity(0.12)
        }

        switch cell.intensityLevel {
        case 1:
            return Color.green.opacity(0.32)
        case 2:
            return Color.green.opacity(0.5)
        case 3:
            return Color.green.opacity(0.72)
        case 4:
            return Color.green.opacity(0.95)
        default:
            return Color(nsColor: .separatorColor).opacity(0.22)
        }
    }

    private func weekdayLabel(for index: Int) -> String {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let symbolIndex = weekdayNumber(for: index) - 1
        return symbols[symbolIndex]
    }

    private func showWeekdayLabel(for index: Int) -> Bool {
        [2, 4, 6].contains(weekdayNumber(for: index))
    }

    private func weekdayNumber(for index: Int) -> Int {
        let calendar = Calendar.current
        return ((calendar.firstWeekday - 1 + index) % DailyUsageHeatmapData.daysPerWeek) + 1
    }

    private func hoverBinding(for cell: DailyUsageHeatmapCell) -> Binding<Bool> {
        Binding(
            get: { hoveredCellID == cell.id },
            set: { isPresented in
                if !isPresented, hoveredCellID == cell.id {
                    hoveredCellID = nil
                }
            }
        )
    }

    private func scheduleHover(for cellID: Date) {
        guard hoveredCellID != cellID else {
            return
        }

        hoverActivationTask?.cancel()
        hoveredCellID = nil
        pendingHoverCellID = cellID

        hoverActivationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: hoverActivationDelayNanoseconds)
            guard !Task.isCancelled, pendingHoverCellID == cellID else {
                return
            }

            pendingHoverCellID = nil
            hoveredCellID = cellID
            hoverActivationTask = nil
        }
    }

    private func cancelHover(for cellID: Date) {
        if pendingHoverCellID == cellID {
            hoverActivationTask?.cancel()
            hoverActivationTask = nil
            pendingHoverCellID = nil
        }

        if hoveredCellID == cellID {
            hoveredCellID = nil
        }
    }
}

private struct DailyUsageHeatmapCellView: View {
    let cell: DailyUsageHeatmapCell
    let color: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary.opacity(cell.hasUsage ? 0.04 : 0), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "\(DailyUsageHeatmapTooltip.dayFormatter.string(from: cell.date)), \(cell.bucket.requestCount) requests, \(cell.bucket.totalTokens) tokens"
    }
}

private struct DailyUsageHeatmapTooltip: View {
    let cell: DailyUsageHeatmapCell

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.dayFormatter.string(from: cell.date))
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                Text(formatCost(cell.bucket.totalCostUsd))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 5) {
                tooltipRow("Total", value: "\(formatTokens(cell.bucket.totalTokens)) tokens")
                tooltipRow("Input", value: "\(formatTokens(cell.bucket.totalInputTokens)) tokens")
                tooltipRow("Output", value: "\(formatTokens(cell.bucket.totalOutputTokens)) tokens")
                tooltipRow("Requests", value: "\(cell.bucket.requestCount)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    private func tooltipRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    private func formatTokens(_ value: Int) -> String {
        value.formatted(.number)
    }

    private func formatCost(_ value: Double) -> String {
        String(format: "$%.4f", value)
    }
}

private struct DailyUsageHeatmapLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("Less")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 1:
            return Color.green.opacity(0.32)
        case 2:
            return Color.green.opacity(0.5)
        case 3:
            return Color.green.opacity(0.72)
        case 4:
            return Color.green.opacity(0.95)
        default:
            return Color(nsColor: .separatorColor).opacity(0.22)
        }
    }
}
