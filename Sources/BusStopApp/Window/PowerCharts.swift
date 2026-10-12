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

/// Series colours, checked with the dataviz palette validator against the
/// card surface (dark mode): every adjacent pair is distinguishable with and
/// without colour-vision deficiency. Teal comes first so a single series stays
/// on brand; amber and coral are left for warnings.
enum PowerChartPalette {
    static let systemInput = Color(hex: 0x0FA396)
    static let battery = Color(hex: 0x5E7CE2)
    /// Third in the system chart, after battery, as in the validated port order.
    static let systemLoad = Color(hex: 0x45A86A)
    static let ports: [Color] = [
        Color(hex: 0x0FA396),
        Color(hex: 0x5E7CE2),
        Color(hex: 0x45A86A),
        Color(hex: 0xA56BD8),
    ]
    /// Ports beyond the palette are summed into one neutral series.
    static let otherPorts = Color(hex: 0x7A8A88)
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

    @State private var hoverDate: Date?

    var body: some View {
        let areaPoints = points.filter { $0.series == areaSeries }
        let areaColor = colorFor(areaSeries)
        let hover = hoverValues()
        let zeroLines: [Double] = showsZeroLine ? [0] : []
        Chart {
            ForEach(areaPoints) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Watts", point.watts))
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
                    series: .value("Series", point.series)
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
                        PowerChartTooltip(hover: item, colorFor: colorFor)
                    }
            }
        }
        .chartForegroundStyleScale(domain: domain, range: colors)
        .chartLegend(position: .top, alignment: .leading, spacing: 10)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Lagoon.stroke)
                AxisValueLabel(format: .dateTime.hour().minute().second())
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
    var colorFor: (String?) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hover.date, format: .dateTime.hour().minute().second())
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

/// Builds chart series from the power history.
enum PowerChartData {
    static let inputName = "System input"
    static let batteryName = "Battery"
    static let loadName = "System load"
    static let otherPortsName = "Other ports"

    /// System input, battery and system load, in legend order.
    static func systemPoints(_ history: PowerHistory, load: [(date: Date, watts: Double)]) -> [PowerChartPoint] {
        let input = history.systemInputSeries.enumerated().map { index, sample in
            PowerChartPoint(id: "in#\(index)", date: sample.date, watts: sample.watts, series: inputName)
        }
        let battery = history.batterySeries.enumerated().map { index, sample in
            PowerChartPoint(id: "bat#\(index)", date: sample.date, watts: sample.watts, series: batteryName)
        }
        let systemLoad = load.enumerated().map { index, sample in
            PowerChartPoint(id: "load#\(index)", date: sample.date, watts: sample.watts, series: loadName)
        }
        return input + battery + systemLoad
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
    static func portSeries(_ history: PowerHistory, title: (PortKey) -> String)
        -> (points: [PowerChartPoint], domain: [String], colors: [Color]) {
        let keys = history.portKeys
        guard !keys.isEmpty else { return ([], [], []) }

        var peaks: [PortKey: Double] = [:]
        for key in keys {
            peaks[key] = history.series(for: key).map { abs($0.watts) }.max() ?? 0
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
            for (index, sample) in history.series(for: key).enumerated() {
                points.append(PowerChartPoint(id: "\(key)#\(index)", date: sample.date, watts: sample.watts, series: name))
            }
        }
        if !folded.isEmpty {
            var sums: [Date: Double] = [:]
            for key in folded {
                for sample in history.series(for: key) { sums[sample.date, default: 0] += sample.watts }
            }
            domain.append(otherPortsName)
            colors.append(PowerChartPalette.otherPorts)
            for (index, date) in sums.keys.sorted().enumerated() {
                points.append(PowerChartPoint(id: "other#\(index)", date: date, watts: sums[date] ?? 0,
                                              series: otherPortsName))
            }
        }
        return (points, domain, colors)
    }
}

// MARK: - System load history

/// The Mac's own power use over time.
///
/// `PortStore.history` (`PowerSample`) keeps system input, battery and port
/// power but not system load, so the Power page records load here, from the
/// same snapshots and over the same span. Recording starts when the topology
/// window first opens.
final class SystemLoadRecorder {
    static let shared = SystemLoadRecorder()

    struct Sample {
        var date: Date
        var milliwatts: Int
    }

    private(set) var samples: [Sample] = []
    private var observation: ObservationLoop?
    /// Matches `PowerHistory`'s defaults.
    private let window: TimeInterval = 600
    private let capacity = 600

    /// Starts following the store's snapshots (once).
    func start(store: PortStore) {
        guard observation == nil else { return }
        observation = ObservationLoop { [weak self, weak store] in
            guard let self, let store else { return }
            self.record(store.snapshot)
        }
    }

    /// Adds the snapshot's load, with the same rules as `PowerHistory.append`:
    /// samples under 0.5 s apart replace each other and a clock that goes
    /// backwards starts over.
    func record(_ snapshot: HostSnapshot) {
        guard let load = snapshot.power.systemLoadMilliwatts else { return }
        let date = snapshot.capturedAt
        if let last = samples.last {
            if date < last.date {
                samples.removeAll()
            } else if date.timeIntervalSince(last.date) < 0.5 {
                samples.removeLast()
            }
        }
        samples.append(Sample(date: date, milliwatts: load))
        let cutoff = date.addingTimeInterval(-window)
        samples.removeAll { $0.date < cutoff }
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    /// Load in watts over the span `history` covers, ending with `current`
    /// even if its sample has not been recorded yet.
    func series(for history: PowerHistory, current: HostSnapshot) -> [(date: Date, watts: Double)] {
        guard let start = history.samples.first?.date else { return [] }
        var result = samples.filter { $0.date >= start }.map { (date: $0.date, watts: Double($0.milliwatts) / 1000) }
        if let load = current.power.systemLoadMilliwatts, current.capturedAt >= start {
            if let last = result.last, current.capturedAt.timeIntervalSince(last.date) < 0.5 {
                result.removeLast()
            }
            result.append((date: current.capturedAt, watts: Double(load) / 1000))
        }
        return result
    }
}
