import SwiftUI
import Charts

/// 按分钟聚合的 token 消耗堆叠柱状图。
/// 少量数据时铺满容器，长时间跨度时按分钟槽位横向滚动。
struct OverviewChartView: View {
    let buckets: [MinuteAggregation]
    let yAxisMode: String  // "tokens" or "cost"
    private let chartData: OverviewChartData

    @State private var hoverSelection: OverviewChartHoverSelection?
    @StateObject private var hoverUpdateCoordinator = OverviewChartHoverUpdateCoordinator()

    private let barWidth: CGFloat = 6
    private let tooltipWidth: CGFloat = 260
    private let minSlots = 6
    private let bucketInterval: TimeInterval = 60
    private let chartTopPadding: CGFloat = 6
    private let chartBottomPadding: CGFloat = 8
    private let tooltipMoveThreshold: CGFloat = 0.5

    init(buckets: [MinuteAggregation], yAxisMode: String) {
        self.buckets = buckets
        self.yAxisMode = yAxisMode
        self.chartData = OverviewChartData(buckets: buckets)
    }

    var body: some View {
        if buckets.isEmpty {
            emptyView
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    chart
                        .frame(maxWidth: .infinity)
                        .frame(height: chartHeight)

                    if let hoverSelection {
                        OverviewChartTooltip(bucket: hoverSelection.bucket, yAxisMode: yAxisMode)
                            .equatable()
                            .frame(width: tooltipWidth)
                            .position(tooltipPosition(for: hoverSelection.location, in: proxy.size))
                            .zIndex(20)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: chartHeight)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No token usage for the selected filters.")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(height: chartHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart

    private var chart: some View {
        OverviewChartPlot(
            chartData: chartData,
            yAxisMode: yAxisMode,
            selectedMinute: hoverSelection?.bucket.minute,
            barWidth: barWidth,
            xDomain: xDomain,
            visibleXDomainLength: visibleXDomainLength,
            minBars: minBars,
            chartTopPadding: chartTopPadding,
            chartBottomPadding: chartBottomPadding
        )
        .equatable()
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateSelection(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            clearSelection()
                        }
                    }
            }
        }
    }

    // MARK: - Sizing

    private var chartHeight: CGFloat { 320 }

    private var xSlotCount: Int {
        guard let first = chartData.sortedBuckets.first?.minute,
              let last = chartData.sortedBuckets.last?.minute else {
            return minSlots
        }
        let span = max(last.timeIntervalSince(first), 0)
        return max(Int(ceil(span / bucketInterval)) + 1, minSlots)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = chartData.sortedBuckets.first?.minute,
              let last = chartData.sortedBuckets.last?.minute else {
            let now = Date()
            return now.addingTimeInterval(-bucketInterval)...now.addingTimeInterval(bucketInterval)
        }
        let leading = first.addingTimeInterval(-bucketInterval)
        let trailing = last.addingTimeInterval(bucketInterval)
        return leading...trailing
    }

    private var visibleXDomainLength: TimeInterval {
        let visibleSlots = min(max(xSlotCount, minSlots), 36)
        return TimeInterval(max(visibleSlots - 1, 1)) * bucketInterval
    }

    private var minBars: Int {
        min(max(xSlotCount, 4), 8)
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            clearSelection()
            return
        }
        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.contains(location) else {
            clearSelection()
            return
        }

        let relativeX = location.x - plotFrame.origin.x
        guard let hoveredDate: Date = proxy.value(atX: relativeX) else {
            clearSelection()
            return
        }

        guard let nextBucket = chartData.nearestBucket(to: hoveredDate, maximumDistance: bucketInterval / 2) else {
            clearSelection()
            return
        }

        updateHoverSelection(bucket: nextBucket, location: location)
    }

    private func clearSelection() {
        hoverUpdateCoordinator.cancel()
        if hoverSelection != nil {
            hoverSelection = nil
        }
    }

    private func updateHoverSelection(bucket: MinuteAggregation, location: CGPoint) {
        let nextSelection = OverviewChartHoverSelection(bucket: bucket, location: location)

        guard let currentSelection = hoverSelection else {
            hoverSelection = nextSelection
            return
        }

        guard currentSelection.bucket.id == bucket.id else {
            hoverUpdateCoordinator.cancel()
            hoverSelection = nextSelection
            return
        }

        if shouldUpdateTooltipLocation(to: location) {
            hoverUpdateCoordinator.schedule(selection: nextSelection) { selection in
                hoverSelection = selection
            }
        }
    }

    private func shouldUpdateTooltipLocation(to location: CGPoint) -> Bool {
        guard let hoverLocation = hoverSelection?.location else {
            return true
        }
        return abs(hoverLocation.x - location.x) > tooltipMoveThreshold ||
            abs(hoverLocation.y - location.y) > tooltipMoveThreshold
    }

    private func tooltipPosition(for location: CGPoint, in size: CGSize) -> CGPoint {
        let xOffset: CGFloat = 18
        let yOffset: CGFloat = -88
        let halfWidth = tooltipWidth / 2
        let x = min(max(location.x + xOffset + halfWidth, halfWidth + 8), size.width - halfWidth - 8)
        let y = max(location.y + yOffset, 18)
        return CGPoint(x: x, y: y)
    }
}

private struct OverviewChartHoverSelection: Equatable {
    let bucket: MinuteAggregation
    let location: CGPoint
}

@MainActor
private final class OverviewChartHoverUpdateCoordinator: ObservableObject {
    private static let frameIntervalNanoseconds: UInt64 = 16_000_000

    private var pendingSelection: OverviewChartHoverSelection?
    private var scheduledTask: Task<Void, Never>?

    func schedule(
        selection: OverviewChartHoverSelection,
        apply: @escaping @MainActor (OverviewChartHoverSelection) -> Void
    ) {
        pendingSelection = selection
        guard scheduledTask == nil else {
            return
        }

        scheduledTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.frameIntervalNanoseconds)
            } catch {
                return
            }
            guard let self, let selection = self.pendingSelection else {
                return
            }
            self.pendingSelection = nil
            self.scheduledTask = nil
            apply(selection)
        }
    }

    func cancel() {
        pendingSelection = nil
        scheduledTask?.cancel()
        scheduledTask = nil
    }
}

private struct OverviewChartPlot: View, Equatable {
    let chartData: OverviewChartData
    let yAxisMode: String
    let selectedMinute: Date?
    let barWidth: CGFloat
    let xDomain: ClosedRange<Date>
    let visibleXDomainLength: TimeInterval
    let minBars: Int
    let chartTopPadding: CGFloat
    let chartBottomPadding: CGFloat

    static func == (lhs: OverviewChartPlot, rhs: OverviewChartPlot) -> Bool {
        lhs.chartData == rhs.chartData &&
            lhs.yAxisMode == rhs.yAxisMode &&
            lhs.selectedMinute == rhs.selectedMinute &&
            lhs.barWidth == rhs.barWidth &&
            lhs.xDomain == rhs.xDomain &&
            lhs.visibleXDomainLength == rhs.visibleXDomainLength &&
            lhs.minBars == rhs.minBars &&
            lhs.chartTopPadding == rhs.chartTopPadding &&
            lhs.chartBottomPadding == rhs.chartBottomPadding
    }

    var body: some View {
        Chart {
            if yAxisMode == "cost" {
                ForEach(chartData.sortedBuckets) { bucket in
                    BarMark(
                        x: .value("Minute", bucket.minute, unit: .minute),
                        y: .value("Cost", bucket.totalCostUsd),
                        width: .fixed(barWidth),
                        stacking: .standard
                    )
                    .foregroundStyle(Color.blue.opacity(0.7))
                }
            } else {
                ForEach(chartData.sortedSegments) { seg in
                    BarMark(
                        x: .value("Minute", seg.minute, unit: .minute),
                        y: .value("Tokens", seg.count),
                        width: .fixed(barWidth),
                        stacking: .standard
                    )
                    .foregroundStyle(by: .value("Dimension", seg.dimension.rawValue))
                }
            }

            if let selectedMinute {
                RuleMark(x: .value("Selected Minute", selectedMinute, unit: .minute))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartForegroundStyleScale(
            domain: TokenDimension.allCases.map(\.rawValue),
            range: TokenDimension.allCases.map { $0.color.opacity(0.7) }
        )
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleXDomainLength)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: minBars)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .padding(.top, 8)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(formatYAxisValue(doubleValue))
                    } else if let intValue = value.as(Int.self) {
                        Text(formatYAxisValue(Double(intValue)))
                    }
                }
            }
        }
        .padding(.top, chartTopPadding)
        .padding(.bottom, chartBottomPadding)
    }

    private func formatYAxisValue(_ value: Double) -> String {
        if yAxisMode == "cost" {
            return String(format: "$%.2f", value)
        }

        let absoluteValue = abs(value)
        if absoluteValue >= 1_000_000 {
            return compact(value / 1_000_000, suffix: "M")
        }
        if absoluteValue >= 1_000 {
            return compact(value / 1_000, suffix: "k")
        }
        return String(format: "%.0f", value)
    }

    private func compact(_ value: Double, suffix: String) -> String {
        if value.rounded() == value {
            return String(format: "%.0f%@", value, suffix)
        }
        return String(format: "%.1f%@", value, suffix)
    }
}

private struct OverviewChartTooltip: View, Equatable {
    let bucket: MinuteAggregation
    let yAxisMode: String

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private var chartedTotalTokens: Int {
        bucket.totalInputTokens + bucket.totalOutputTokens + bucket.totalCachedTokens
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(formatDate(bucket.minute))
                    .fontWeight(.semibold)
                Spacer(minLength: 12)
                Text(primaryValue)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                if yAxisMode == "cost" {
                    HStack {
                        Text("Cost")
                        Spacer()
                        Text(formatCost(bucket.totalCostUsd))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Requests")
                        Spacer()
                        Text("\(bucket.requestCount)")
                            .monospacedDigit()
                    }
                } else {
                    tooltipRow(color: TokenDimension.input.color, label: "Input", value: bucket.totalInputTokens)
                    tooltipRow(color: TokenDimension.output.color, label: "Output", value: bucket.totalOutputTokens)
                    tooltipRow(color: TokenDimension.cached.color, label: "Cached", value: bucket.totalCachedTokens)

                    if bucket.totalReasoningTokens > 0 {
                        tooltipRow(color: .purple, label: "Reasoning", value: bucket.totalReasoningTokens)
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(width: 260)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    private var primaryValue: String {
        if yAxisMode == "cost" {
            return formatCost(bucket.totalCostUsd)
        }
        return "\(formatTokens(chartedTotalTokens)) tokens"
    }

    private func tooltipRow(color: Color, label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.75))
                .frame(width: 10, height: 10)
            Text(label)
            Spacer()
            Text("\(formatTokens(value)) tokens")
                .monospacedDigit()
        }
    }

    private func formatDate(_ date: Date) -> String {
        Self.minuteFormatter.string(from: date)
    }

    private func formatTokens(_ value: Int) -> String {
        value.formatted(.number)
    }

    private func formatCost(_ value: Double) -> String {
        String(format: "$%.4f", value)
    }
}

// MARK: - Legend

struct OverviewLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: TokenDimension.input.color.opacity(0.7), label: "Input")
            legendItem(color: TokenDimension.output.color.opacity(0.7), label: "Output")
            legendItem(color: TokenDimension.cached.color.opacity(0.7), label: "Cached")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}
