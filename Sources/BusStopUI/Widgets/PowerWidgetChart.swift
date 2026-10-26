import BusStopCore
import Charts
import SwiftUI
import WidgetKit

/// Builds the Power widget's chart lines from the payload.
///
/// The payload carries the last 10 minutes at full rate and the day at
/// 5-minute steps. The hour chart joins the two: the day's steps from an
/// hour ago up to where the live buffer starts, then the live buffer
/// averaged per minute, so the newest stretch is not a much noisier line
/// than the rest.
enum PowerWidgetData {
    /// A longer silence than this breaks a line; 5-minute steps join, a
    /// missing step or two (sleep, the app not running) does not.
    static let maxGap = WidgetPayload.dayPowerStep * 2.5

    /// One plotted quantity.
    enum Series: String, CaseIterable {
        case input = "In"
        case load = "Load"
        case devices = "Out"

        var name: String { rawValue }

        func watts(_ sample: PowerSample) -> Double? {
            switch self {
            case .input: sample.systemInputMilliwatts.map { Double($0) / 1000 }
            case .load: sample.systemLoadMilliwatts.map { Double($0) / 1000 }
            case .devices: Double(sample.portMilliwatts.values.filter { $0 > 0 }.reduce(0, +)) / 1000
            }
        }
    }

    /// What the charts plot: power in and what the Mac uses while a charger
    /// delivers, what the Mac uses on battery, and otherwise (a desktop that
    /// reports neither) what the ports give to devices.
    static func series(_ payload: WidgetPayload) -> [Series] {
        let samples = payload.recentPower + payload.dayPower
        let hasLoad = samples.contains { $0.systemLoadMilliwatts != nil }
        if samples.contains(where: { ($0.systemInputMilliwatts ?? 0) > 0 }) {
            return hasLoad ? [.input, .load] : [.input]
        }
        return hasLoad ? [.load] : [.devices]
    }

    /// The last hour of one series, oldest first.
    static func hourValues(_ series: Series, _ payload: WidgetPayload) -> [(date: Date, watts: Double)] {
        let start = payload.capturedAt - PowerRange.hour.span
        let liveStart = payload.recentPower.first?.date ?? payload.capturedAt
        // Only steps that end before the live buffer begins, so no minute is counted twice.
        let older = payload.dayPower
            .filter { $0.date >= start && $0.date + WidgetPayload.dayPowerStep <= liveStart }
            .compactMap { sample in series.watts(sample).map { (date: sample.date, watts: $0) } }
        let live = payload.recentPower
            .filter { $0.date >= start }
            .compactMap { sample in series.watts(sample).map { (date: sample.date, watts: $0) } }
        return older + minuteMeans(live)
    }

    /// The last 24 hours of one series, oldest first.
    static func dayValues(_ series: Series, _ payload: WidgetPayload) -> [(date: Date, watts: Double)] {
        let start = payload.capturedAt - PowerRange.day.span
        return payload.dayPower
            .filter { $0.date >= start }
            .compactMap { sample in series.watts(sample).map { (date: sample.date, watts: $0) } }
    }

    /// Values averaged per clock minute, each dated at its minute's start.
    static func minuteMeans(_ values: [(date: Date, watts: Double)]) -> [(date: Date, watts: Double)] {
        var buckets: [(date: Date, total: Double, count: Int)] = []
        for value in values {
            let minute = Date(timeIntervalSinceReferenceDate:
                (value.date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
            if buckets.last?.date == minute {
                buckets[buckets.count - 1].total += value.watts
                buckets[buckets.count - 1].count += 1
            } else {
                buckets.append((minute, value.watts, 1))
            }
        }
        return buckets.map { (date: $0.date, watts: $0.total / Double($0.count)) }
    }

    /// Chart points for every series over `range` (`.hour` or `.day`).
    static func points(_ payload: WidgetPayload, range: PowerRange) -> [PowerChartPoint] {
        series(payload).flatMap { series in
            let values = range == .day ? dayValues(series, payload) : hourValues(series, payload)
            return PowerChartData.points(values, series: series.name, id: "\(series)", maxGap: maxGap)
        }
    }

    /// Round clock times for the time axis: quarter hours over the hour, every
    /// six hours over the day. Swift Charts' own strides count from the
    /// domain's start, which gives times such as 8:28.
    static func axisDates(_ range: PowerRange, end: Date, calendar: Calendar = .current) -> [Date] {
        let start = end - range.span
        guard var date = calendar.dateInterval(of: .hour, for: start)?.start else { return [] }
        var dates: [Date] = []
        while date <= end {
            if date >= start, range != .day || calendar.component(.hour, from: date) % 6 == 0 { dates.append(date) }
            date += range == .day ? 3_600 : 900
        }
        return dates
    }

    /// "Last hour", or "Since 14:05" when the data starts later than the range would reach.
    static func spanText(_ points: [PowerChartPoint], range: PowerRange, end: Date) -> String {
        guard let first = points.map(\.date).min(), first > end - range.span + maxGap else { return range.spanText }
        return "Since " + first.formatted(.dateTime.hour().minute())
    }
}

/// A titled power chart for the widget: a filled first series and a dashed
/// second one, so the two lines differ by more than colour and still read
/// when the desktop renders the widget in monochrome.
struct PowerWidgetChartSection: View {
    var payload: WidgetPayload
    var range: PowerRange

    var body: some View {
        let points = PowerWidgetData.points(payload, range: range)
        let names = PowerWidgetData.series(payload).map(\.name)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(PowerWidgetData.spanText(points, range: range, end: payload.capturedAt))
                    .lagoonFont(.caption, weight: .semibold)
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    PowerWidgetLegendItem(name: name, isPrimary: index == 0)
                }
            }
            if points.isEmpty {
                Text("No power readings yet")
                    .lagoonFont(.callout)
                    .foregroundStyle(Lagoon.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PowerWidgetChart(points: points, domain: names, range: range, end: payload.capturedAt)
            }
        }
        .frame(minHeight: 96, idealHeight: 96, maxHeight: .infinity)
    }
}

/// A short line swatch and the series name.
struct PowerWidgetLegendItem: View {
    var name: String
    var isPrimary: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: 4) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 12, y: 1))
            }
            .stroke(PowerWidgetChart.color(isPrimary: isPrimary, renderingMode),
                    style: PowerWidgetChart.stroke(isPrimary: isPrimary))
            .frame(width: 12, height: 2)
            Text(name)
                .lagoonFont(.caption)
                .foregroundStyle(Lagoon.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// The plot itself. Built from plain marks with no hover overlay, since a
/// widget gets no pointer events.
struct PowerWidgetChart: View {
    var points: [PowerChartPoint]
    var domain: [String]
    var range: PowerRange
    var end: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Full colour uses the app's series colours; vibrant and accented
    /// rendering keep only luminance, so the second line is drawn dimmer.
    static func color(isPrimary: Bool, _ mode: WidgetRenderingMode) -> Color {
        if mode == .fullColor { return isPrimary ? PowerChartPalette.systemInput : PowerChartPalette.systemLoad }
        return isPrimary ? Lagoon.textPrimary : Lagoon.textSecondary
    }

    static func stroke(isPrimary: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: isPrimary ? 2 : 1.5, lineCap: .round, lineJoin: .round, dash: isPrimary ? [] : [3, 3])
    }

    var body: some View {
        let primary = domain.first
        let areaPoints = points.filter { $0.series == primary }
        let areaColor = Self.color(isPrimary: true, renderingMode)
        let colors = domain.indices.map { Self.color(isPrimary: $0 == 0, renderingMode) }
        Chart {
            ForEach(areaPoints) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Watts", point.watts),
                         series: .value("Segment", point.segment), stacking: .unstacked)
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [areaColor.opacity(0.3), areaColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            ForEach(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("Watts", point.watts),
                         series: .value("Series", "\(point.series)#\(point.segment)"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Series", point.series))
                    .lineStyle(Self.stroke(isPrimary: point.series == primary))
            }
            // A one-point segment draws no line, so mark it with a dot.
            ForEach(PowerChartData.isolated(points)) { point in
                PointMark(x: .value("Time", point.date), y: .value("Watts", point.watts))
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbolSize(12)
            }
        }
        .chartForegroundStyleScale(domain: domain, range: colors)
        .chartLegend(.hidden)
        .chartXScale(domain: (end - range.span)...end)
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXAxis {
            AxisMarks(values: PowerWidgetData.axisDates(range, end: end)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Lagoon.stroke)
                AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.hour().minute())
                    .foregroundStyle(Lagoon.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Lagoon.stroke)
                AxisValueLabel {
                    if let watts = value.as(Double.self) { Text("\(Int(watts.rounded())) W") }
                }
                .foregroundStyle(Lagoon.textTertiary)
            }
        }
    }
}
