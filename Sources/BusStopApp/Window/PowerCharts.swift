import BusStopCore
import Charts
import SwiftUI

// Power-over-time charts. Series arrays are built before the Chart and the
// Chart body only contains ForEach blocks (no `if`), which keeps Swift Charts
// happy when deploying to macOS 26.

/// One plotted sample.
nonisolated struct PowerChartPoint: Identifiable, Sendable {
    var id: String
    var date: Date
    var watts: Double
    var series: String
    /// Points of one series in different segments are not joined, so a line
    /// breaks across a gap such as sleep.
    var segment = 0
}

/// The values under the pointer, for the tooltip.
nonisolated struct PowerChartHover: Identifiable, Sendable {
    nonisolated struct Entry: Identifiable, Sendable {
        var series: String
        var watts: Double
        var id: String { series }
    }

    var date: Date
    var entries: [Entry]
    var id: Date { date }
}

/// A line chart of watts over time with an optional filled series, a zero
/// line and a hover crosshair with a tooltip.
struct PowerLineChart: View {
    var points: [PowerChartPoint]
    /// Series names in legend order, with matching colours.
    var domain: [String]
    var colors: [Color]
    /// Series drawn with a soft area fill under its line.
    var areaSeries: String?
    var showsZeroLine: Bool = false
    var range: PowerRange = .tenMinutes

    @State private var hoverDate: Date?

    var body: some View {
        let areaPoints = points.filter { $0.series == areaSeries }
        let areaColor = colorFor(areaSeries)
        let hover = hoverValues()
        let zeroLines: [Double] = showsZeroLine ? [0] : []
        Chart {
            ForEach(areaPoints) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Watts", point.watts),
                         series: .value("Segment", point.segment), stacking: .unstacked)
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(colors: [areaColor.opacity(0.32), areaColor.opacity(0.0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
            ForEach(zeroLines, id: \.self) { value in
                RuleMark(y: .value("Zero", value))
                    .foregroundStyle(Lagoon.strokeStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Watts", point.watts),
                    series: .value("Series", "\(point.series)#\(point.segment)")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(by: .value("Series", point.series))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            ForEach(hover) { item in
                RuleMark(x: .value("Time", item.date))
                    .foregroundStyle(Lagoon.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        PowerChartTooltip(hover: item, format: range.tooltipFormat, colorFor: colorFor)
                    }
            }
        }
        .chartForegroundStyleScale(domain: domain, range: colors)
        .chartLegend(position: .top, alignment: .leading, spacing: 10)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Lagoon.stroke)
                AxisValueLabel(format: range.axisFormat)
                    .foregroundStyle(Lagoon.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Lagoon.stroke)
                AxisValueLabel()
                    .foregroundStyle(Lagoon.textTertiary)
            }
        }
        .chartYAxisLabel("W")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let origin = geometry[plotFrame].origin
                            hoverDate = proxy.value(atX: location.x - origin.x, as: Date.self)
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
    }

    private func colorFor(_ series: String?) -> Color {
        guard let series, let index = domain.firstIndex(of: series), index < colors.count else {
            return Lagoon.accent
        }
        return colors[index]
    }

    /// The sample nearest the pointer, with each series' value at that time.
    private func hoverValues() -> [PowerChartHover] {
        guard let hoverDate, !points.isEmpty else { return [] }
        let dates = Set(points.map(\.date))
        guard let nearest = dates.min(by: {
            abs($0.timeIntervalSince(hoverDate)) < abs($1.timeIntervalSince(hoverDate))
        }) else { return [] }
        let entries = domain.compactMap { series -> PowerChartHover.Entry? in
            guard let point = points.first(where: { $0.series == series && $0.date == nearest }) else { return nil }
            return PowerChartHover.Entry(series: series, watts: point.watts)
        }
        return [PowerChartHover(date: nearest, entries: entries)]
    }
}

/// Tooltip shown at the crosshair: the time and each series' value.
struct PowerChartTooltip: View {
    var hover: PowerChartHover
    var format: Date.FormatStyle
    var colorFor: (String?) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hover.date, format: format)
                .lagoonFont(.caption2, weight: .semibold)
                .foregroundStyle(Lagoon.textSecondary)
            ForEach(hover.entries) { entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorFor(entry.series))
                        .frame(width: 7, height: 7)
                    Text(entry.series)
                        .foregroundStyle(Lagoon.textSecondary)
                    Spacer(minLength: 8)
                    Text(Format.power(milliwatts: Int((entry.watts * 1000).rounded())))
                        .foregroundStyle(Lagoon.textPrimary)
                }
                .lagoonFont(.caption, monospacedDigits: true)
            }
        }
        .padding(8)
        .frame(minWidth: 150)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Lagoon.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Lagoon.strokeStrong, lineWidth: 1))
    }
}

/// How far back the Power page's charts reach. Ten minutes is the live
/// buffer; the longer ranges read the saved history.
enum PowerRange: CaseIterable, Identifiable {
    case tenMinutes, hour, day, week

    var id: Self { self }

    var title: String {
        switch self {
        case .tenMinutes: "10 min"
        case .hour: "1 h"
        case .day: "24 h"
        case .week: "7 d"
        }
    }

    var spanText: String {
        switch self {
        case .tenMinutes: "Last 10 minutes"
        case .hour: "Last hour"
        case .day: "Last 24 hours"
        case .week: "Last 7 days"
        }
    }

    var span: TimeInterval {
        switch self {
        case .tenMinutes: 600
        case .hour: 3_600
        case .day: 86_400
        case .week: 7 * 86_400
        }
    }

    /// Seconds averaged into one point of the saved history; a week of
    /// minutes would be 10,080 points per series.
    var step: TimeInterval { self == .week ? 600 : 60 }

    /// A longer silence than this breaks the lines. Live power arrives every
    /// 2 to 10 s while the screens are on; saved points are `step` apart.
    var maxGap: TimeInterval { self == .tenMinutes ? 30 : step * 2.5 }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .tenMinutes: .dateTime.hour().minute().second()
        case .hour, .day: .dateTime.hour().minute()
        case .week: .dateTime.weekday(.abbreviated).day()
        }
    }

    var tooltipFormat: Date.FormatStyle {
        switch self {
        case .tenMinutes: .dateTime.hour().minute().second()
        case .hour: .dateTime.hour().minute()
        case .day, .week: .dateTime.weekday(.abbreviated).hour().minute()
        }
    }
}

/// Builds chart series from power samples, oldest first.
enum PowerChartData {
    static let inputName = "System input"
    static let batteryName = "Battery"
    static let loadName = "System load"
    static let otherPortsName = "Other ports"

    /// System input, battery and system load, in legend order.
    static func systemPoints(_ samples: [PowerSample], maxGap: TimeInterval) -> [PowerChartPoint] {
        points(samples.systemInputSeries, series: inputName, id: "in", maxGap: maxGap)
            + points(samples.batterySeries, series: batteryName, id: "bat", maxGap: maxGap)
            + points(samples.systemLoadSeries, series: loadName, id: "load", maxGap: maxGap)
    }

    /// One series' points, split into segments at gaps longer than `maxGap`.
    static func points(_ values: [(date: Date, watts: Double)], series: String, id: String,
                       maxGap: TimeInterval) -> [PowerChartPoint] {
        let segments = PowerSample.segments(values.map(\.date), maxGap: maxGap)
        return values.enumerated().map { index, value in
            PowerChartPoint(id: "\(id)#\(index)", date: value.date, watts: value.watts, series: series,
                            segment: segments[index])
        }
    }

    static func systemColor(_ series: String) -> Color {
        switch series {
        case inputName: return PowerChartPalette.systemInput
        case loadName: return PowerChartPalette.systemLoad
        default: return PowerChartPalette.battery
        }
    }

    /// Per-port series: the busiest ports get their own colour, the rest are
    /// summed into "Other ports".
    static func portSeries(_ samples: [PowerSample], title: (PortKey) -> String, maxGap: TimeInterval)
        -> (points: [PowerChartPoint], domain: [String], colors: [Color]) {
        let keys = samples.portKeys
        guard !keys.isEmpty else { return ([], [], []) }

        var peaks: [PortKey: Double] = [:]
        for key in keys {
            peaks[key] = samples.series(for: key).map { abs($0.watts) }.max() ?? 0
        }
        // Busiest first; ties keep physical order.
        let ranked = keys.enumerated().sorted { lhs, rhs in
            let left = peaks[lhs.element] ?? 0
            let right = peaks[rhs.element] ?? 0
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map { $0.element }
        let palette = PowerChartPalette.ports
        let ownSeries = ranked.count > palette.count ? Array(ranked.prefix(palette.count - 1)) : ranked
        let folded = ranked.count > palette.count ? Array(ranked.dropFirst(palette.count - 1)) : []

        var points: [PowerChartPoint] = []
        var domain: [String] = []
        var colors: [Color] = []
        // Keep physical order in the legend, colours by rank.
        for key in keys where ownSeries.contains(key) {
            var name = title(key)
            if domain.contains(name) { name += " (\(key))" }
            domain.append(name)
            colors.append(palette[ownSeries.firstIndex(of: key) ?? 0])
            points += Self.points(samples.series(for: key), series: name, id: "\(key)", maxGap: maxGap)
        }
        if !folded.isEmpty {
            var sums: [Date: Double] = [:]
            for key in folded {
                for sample in samples.series(for: key) { sums[sample.date, default: 0] += sample.watts }
            }
            domain.append(otherPortsName)
            colors.append(PowerChartPalette.otherPorts)
            let other = sums.keys.sorted().map { (date: $0, watts: sums[$0] ?? 0) }
            points += Self.points(other, series: otherPortsName, id: "other", maxGap: maxGap)
        }
        return (points, domain, colors)
    }
}
