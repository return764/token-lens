import SwiftUI
import Charts

/// 按 10 分钟聚合的 token 消耗堆叠柱状图。
/// 少量数据时铺满容器，长时间跨度时按 10 分钟槽位横向滚动。
struct OverviewChartView: View {
    let buckets: [MinuteAggregation]
    let yAxisMode: String  // "tokens" or "cost"

    @State private var selectedBucket: MinuteAggregation?
    @State private var hoverLocation: CGPoint?

    private let barSlotWidth: CGFloat = 42
    private let barWidth: CGFloat = 10
    private let tooltipWidth: CGFloat = 260
    private let minSlots = 6
    private let horizontalPadding: CGFloat = 12
    private let bucketInterval: TimeInterval = 10 * 60

    var body: some View {
        if buckets.isEmpty {
            emptyView
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        chart
                            .frame(width: max(chartWidth, proxy.size.width - horizontalPadding * 2))
                            .frame(height: chartHeight)
                            .padding(.horizontal, horizontalPadding)
                    }

                    if let selectedBucket, let hoverLocation {
                        OverviewChartTooltip(bucket: selectedBucket, yAxisMode: yAxisMode)
                            .frame(width: tooltipWidth)
                            .position(tooltipPosition(for: hoverLocation, in: proxy.size))
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
        Chart {
            if yAxisMode == "cost" {
                ForEach(sortedBuckets) { bucket in
                    BarMark(
                        x: .value("Minute", bucket.minute, unit: .minute),
                        y: .value("Cost", bucket.totalCostUsd),
                        width: .fixed(barWidth),
                        stacking: .standard
                    )
                    .foregroundStyle(Color.blue.opacity(0.7))
                }
            } else {
                ForEach(sortedSegments) { seg in
                    BarMark(
                        x: .value("Minute", seg.minute, unit: .minute),
                        y: .value("Tokens", seg.count),
                        width: .fixed(barWidth),
                        stacking: .standard
                    )
                    .foregroundStyle(by: .value("Dimension", seg.dimension.rawValue))
                }
            }

            if let selectedBucket {
                RuleMark(x: .value("Selected Minute", selectedBucket.minute, unit: .minute))
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
        .chartYScale(domain: 0...yAxisUpperBound)
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
        .padding(.top, 6)
        .padding(.bottom, 8)
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
                            selectedBucket = nil
                            hoverLocation = nil
                        }
                    }
            }
        }
    }

    // MARK: - Data helpers

    private var sortedBuckets: [MinuteAggregation] {
        buckets.sorted(by: { $0.minute < $1.minute })
    }

    private var sortedSegments: [BarSegment] {
        buckets.toBarSegments()
    }

    // MARK: - Sizing

    private var chartHeight: CGFloat { 320 }

    private var chartWidth: CGFloat {
        CGFloat(xSlotCount) * barSlotWidth
    }

    private var xSlotCount: Int {
        guard let first = sortedBuckets.first?.minute,
              let last = sortedBuckets.last?.minute else {
            return minSlots
        }
        let span = max(last.timeIntervalSince(first), 0)
        return max(Int(ceil(span / bucketInterval)) + 1, minSlots)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = sortedBuckets.first?.minute,
              let last = sortedBuckets.last?.minute else {
            let now = Date()
            return now.addingTimeInterval(-bucketInterval)...now.addingTimeInterval(bucketInterval)
        }
        let leading = first.addingTimeInterval(-bucketInterval)
        let trailing = last.addingTimeInterval(bucketInterval)
        return leading...trailing
    }

    private var yAxisUpperBound: Double {
        let maxValue: Double
        if yAxisMode == "cost" {
            maxValue = sortedBuckets.map(\.totalCostUsd).max() ?? 0
        } else {
            maxValue = sortedBuckets
                .map { Double($0.totalInputTokens + $0.totalOutputTokens + $0.totalCachedTokens) }
                .max() ?? 0
        }
        return max(maxValue * 1.12, 1)
    }

    private var minBars: Int {
        min(max(xSlotCount, 4), 8)
    }

    private func formatYAxisValue(_ value: Double) -> String {
        if yAxisMode == "cost" {
            if value < 0.01 {
                return String(format: "$%.4f", value)
            }
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

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            selectedBucket = nil
            hoverLocation = nil
            return
        }
        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.contains(location) else {
            selectedBucket = nil
            hoverLocation = nil
            return
        }

        let relativeX = location.x - plotFrame.origin.x
        guard let hoveredDate: Date = proxy.value(atX: relativeX) else {
            selectedBucket = nil
            hoverLocation = nil
            return
        }

        selectedBucket = nearestBucket(to: hoveredDate)
        hoverLocation = selectedBucket == nil ? nil : location
    }

    private func nearestBucket(to date: Date) -> MinuteAggregation? {
        guard let nearest = sortedBuckets.min(by: {
            abs($0.minute.timeIntervalSince(date)) < abs($1.minute.timeIntervalSince(date))
        }) else {
            return nil
        }

        let distance = abs(nearest.minute.timeIntervalSince(date))
        return distance <= bucketInterval / 2 ? nearest : nil
    }

    private func tooltipPosition(for location: CGPoint, in size: CGSize) -> CGPoint {
        let xOffset: CGFloat = 18
        let yOffset: CGFloat = -88
        let halfWidth = tooltipWidth / 2
        let x = min(max(location.x + horizontalPadding + xOffset + halfWidth, halfWidth + 8), size.width - halfWidth - 8)
        let y = max(location.y + yOffset, 18)
        return CGPoint(x: x, y: y)
    }
}

private struct OverviewChartTooltip: View {
    let bucket: MinuteAggregation
    let yAxisMode: String

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
                tooltipRow(color: TokenDimension.input.color, label: "Input", value: bucket.totalInputTokens)
                tooltipRow(color: TokenDimension.output.color, label: "Output", value: bucket.totalOutputTokens)
                tooltipRow(color: TokenDimension.cached.color, label: "Cached", value: bucket.totalCachedTokens)

                if bucket.totalReasoningTokens > 0 {
                    tooltipRow(color: .purple, label: "Reasoning", value: bucket.totalReasoningTokens)
                }

                Divider()
                HStack {
                    Text("Total")
                    Spacer()
                    Text("\(formatTokens(bucket.totalTokens)) tokens")
                        .monospacedDigit()
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
            return String(format: "$%.4f", bucket.totalCostUsd)
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatTokens(_ value: Int) -> String {
        value.formatted(.number)
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
