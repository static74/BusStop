import BusStopCore
import SwiftUI
import WidgetKit

/// The Health widget: the current findings in plain English, flaky
/// connections with their likely cause, or "All links healthy". Extra Large
/// adds the recent events and a 7-day strip per port. Severity is always a
/// symbol and words as well as a colour, so it reads in vibrant rendering.
public struct HealthWidgetView: View {
    let entry: WidgetTimeline.Entry
    let family: WidgetFamily

    public init(entry: WidgetTimeline.Entry, family: WidgetFamily) {
        self.entry = entry
        self.family = family
    }

    public var body: some View {
        WidgetChrome("Health", symbol: "stethoscope", entry: entry) { payload in
            let model = HealthWidgetModel(payload)
            if family == .systemExtraLarge {
                HStack(alignment: .top, spacing: 16) {
                    HealthFindings(model: model, showsWeek: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Rectangle()
                        .fill(Lagoon.stroke)
                        .frame(width: 1)
                    HealthHistory(model: model, capturedAt: payload.capturedAt)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                HealthFindings(model: model, showsWeek: true)
            }
        }
        .widgetURL(BusStopLink.page(.diagnostics).url)
    }
}

/// The findings, most severe first, as many as fit; or "All links healthy".
struct HealthFindings: View {
    let model: HealthWidgetModel
    /// The 7-day total under the findings, where no strip shows it.
    let showsWeek: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.findings.isEmpty {
                HealthAllClear()
            } else {
                if model.isHealthy {
                    Label {
                        Text("All links healthy").foregroundStyle(Lagoon.textPrimary)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Lagoon.accent).widgetAccentable()
                    }
                    .lagoonFont(.title3, weight: .semibold)
                }
                HealthSectionLabel(model.isHealthy ? PopoverText.count(model.findings.count, "note", "notes")
                                                   : model.headline)
                list
            }
            if showsWeek, let week = model.week {
                Label {
                    Text(week).foregroundStyle(Lagoon.textSecondary)
                } icon: {
                    Image(systemName: "calendar").foregroundStyle(Lagoon.textTertiary)
                }
                .lagoonFont(.caption)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Every finding with what to do about it if they fit, else without that;
    /// else the first few in detail and the rest by title, else fewer.
    private var list: some View {
        let count = model.findings.count
        let fewer = stride(from: count - 1, through: 1, by: -1)
        // (shown, detailed, level), the first choice first.
        let choices: [(Int, Int, HealthFindingRow.Level)] = [(count, count, .full), (count, count, .detail)]
            + fewer.map { (count, $0, .detail) } + fewer.map { ($0, $0, .detail) }
            + [(min(count, 6), 0, .detail), (min(count, 3), 0, .detail)]
        return ViewThatFits(in: .vertical) {
            ForEach(choices.indices, id: \.self) { index in
                rows(choices[index].0, detailed: choices[index].1, level: choices[index].2)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The first `shown` findings, the first `detailed` of them at `level` and the rest by title.
    private func rows(_ shown: Int, detailed: Int, level: HealthFindingRow.Level) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.findings.prefix(detailed)) { finding in
                HealthFindingRow(finding: finding, level: level)
            }
            if shown > detailed {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(model.findings[detailed..<shown]) { finding in
                        HealthFindingRow(finding: finding, level: .title)
                    }
                }
            }
            if shown < model.findings.count {
                Text("\(model.findings.count - shown) more in Diagnostics")
                    .lagoonFont(.caption, weight: .medium)
                    .foregroundStyle(Lagoon.textSecondary)
                    .padding(.leading, HealthFindingRow.textInset)
            }
        }
    }
}

/// One finding: severity symbol, title, the likely cause, the detail and the suggestion.
struct HealthFindingRow: View {
    enum Level {
        case title
        /// Adds the likely cause and the detail.
        case detail
        /// Adds the suggestion.
        case full
    }

    let finding: Diagnostic
    let level: Level

    /// Where the text starts, past the symbol.
    static let textInset: CGFloat = 24

    var body: some View {
        let color = Lagoon.severityColor(finding.severity)
        let (cause, rest) = HealthWidgetModel.likelyCause(finding.detail)
        let row = HStack(alignment: .firstTextBaseline, spacing: 0) {
            Image(systemName: Lagoon.severitySymbol(finding.severity))
                .lagoonFont(.callout, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: Self.textInset, alignment: .leading)
                .accessibilityLabel(Lagoon.severityName(finding.severity))
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .lagoonFont(.callout, weight: .semibold)
                    .foregroundStyle(Lagoon.textPrimary)
                    .lineLimit(level == .title ? 1 : 2)
                if level != .title {
                    if let cause {
                        Text(cause)
                            .lagoonFont(.caption, weight: .semibold)
                            .foregroundStyle(color)
                    }
                    if !rest.isEmpty {
                        Text(rest)
                            .lagoonFont(.caption)
                            .foregroundStyle(Lagoon.textSecondary)
                            .lineLimit(3)
                    }
                }
                if level == .full, let suggestion = finding.suggestion, !suggestion.isEmpty {
                    Label {
                        Text(suggestion).foregroundStyle(Lagoon.textPrimary)
                    } icon: {
                        Image(systemName: "lightbulb").foregroundStyle(Lagoon.accent).widgetAccentable()
                    }
                    .lagoonFont(.caption)
                    .lineLimit(3)
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        if let key = finding.portKey {
            HealthLink(.port(key)) { row }
        } else {
            row
        }
    }
}

/// No findings at all.
struct HealthAllClear: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .lagoonFont(size: 34, weight: .semibold)
                .foregroundStyle(Lagoon.accent)
                .widgetAccentable()
                .accessibilityHidden(true)
            Text("All links healthy")
                .lagoonFont(.title3, weight: .semibold)
                .foregroundStyle(Lagoon.textPrimary)
            Text("Every link runs as fast as both ends allow, chargers and hubs are within budget, "
                 + "and no port reports a problem.")
                .lagoonFont(.callout)
                .foregroundStyle(Lagoon.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Extra Large's right column: the newest events, then the 7-day strip.
struct HealthHistory: View {
    let model: HealthWidgetModel
    let capturedAt: Date

    var body: some View {
        if model.strip != nil || !model.events.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                events
                if let strip = model.strip, !strip.isEmpty {
                    HealthStrip(rows: strip, days: model.days)
                        .layoutPriority(1)
                }
            }
        } else {
            WidgetNotice("History is off",
                         detail: "Turn on “Keep history between launches” in Settings › Advanced "
                             + "to see recent events and each port’s last 7 days.")
        }
    }

    private var events: some View {
        VStack(alignment: .leading, spacing: 8) {
            HealthSectionLabel("Recent events")
            if model.events.isEmpty {
                Text("Connections, link changes and chargers appear here as they happen.")
                    .lagoonFont(.caption)
                    .foregroundStyle(Lagoon.textSecondary)
            } else {
                HealthLink(.page(.events)) {
                    ViewThatFits(in: .vertical) {
                        ForEach(Array(stride(from: min(model.events.count, 8), through: 1, by: -1)), id: \.self) { n in
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(model.events.prefix(n)) { event in
                                    HealthEventRow(event: event, capturedAt: capturedAt)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// One event: kind symbol, title, where, and when.
struct HealthEventRow: View {
    let event: ConnectionEvent
    let capturedAt: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Image(systemName: event.symbolName)
                .lagoonFont(.caption, weight: .semibold)
                .foregroundStyle(Self.tint(event))
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .lagoonFont(.caption, weight: .semibold)
                    .foregroundStyle(Lagoon.textPrimary)
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .lagoonFont(.caption2)
                        .foregroundStyle(Lagoon.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(Self.time(event.date, capturedAt: capturedAt))
                .lagoonFont(.caption2, monospacedDigits: true)
                .foregroundStyle(Lagoon.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Turquoise for normal activity; amber only for slower links and findings, as on the Events page.
    static func tint(_ event: ConnectionEvent) -> Color {
        switch event.kind {
        case .deviceConnected, .displayConnected: return Lagoon.accent
        case .deviceDisconnected, .displayDisconnected, .chargerDisconnected: return Lagoon.textSecondary
        case .linkChanged: return event.isDowngrade ? Lagoon.warning : Lagoon.accent
        case .chargerConnected: return Lagoon.powerIn
        case .diagnosticRaised: return Lagoon.warning
        }
    }

    /// "14:32" on the day of the capture, "Mon 14:32" before it; never relative, which would go stale.
    static func time(_ date: Date, capturedAt: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: capturedAt)
            ? date.formatted(.dateTime.hour().minute())
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// One row per port: a cell per day, oldest first, and the week in words.
struct HealthStrip: View {
    let rows: [HealthWidgetModel.PortWeek]
    let days: [Date]

    static let nameWidth: CGFloat = 92
    static let cell: CGFloat = 14
    static let cellSpacing: CGFloat = 4
    static let maxRows = 6

    var body: some View {
        // A Mac with many ports leaves out the ones with nothing on record first.
        let shown = rows.count > Self.maxRows ? rows.filter { $0.days.contains { $0 != .quiet } } : rows
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                HealthSectionLabel("Last 7 days")
                    .frame(width: Self.nameWidth, alignment: .leading)
                HStack(spacing: Self.cellSpacing) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        Text(day, format: .dateTime.weekday(.narrow))
                            .lagoonFont(.caption2, weight: index == days.count - 1 ? .bold : .regular)
                            .foregroundStyle(index == days.count - 1 ? Lagoon.textPrimary : Lagoon.textTertiary)
                            .frame(width: Self.cell)
                    }
                }
                .accessibilityHidden(true)
            }
            ForEach(shown.prefix(Self.maxRows)) { row in
                HealthLink(.port(row.key)) {
                    HStack(spacing: 0) {
                        Text(row.title)
                            .lagoonFont(.caption, weight: .medium)
                            .foregroundStyle(Lagoon.textPrimary)
                            .lineLimit(1)
                            .frame(width: Self.nameWidth, alignment: .leading)
                        HStack(spacing: Self.cellSpacing) {
                            ForEach(Array(row.days.enumerated()), id: \.offset) { _, day in
                                HealthDayCell(day: day)
                            }
                        }
                        Text(row.summary)
                            .lagoonFont(.caption2)
                            .foregroundStyle(Lagoon.textSecondary)
                            .lineLimit(1)
                            .padding(.leading, 10)
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title): \(row.summary) in the last 7 days")
            }
            legend
                .padding(.top, 2)
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([HealthWidgetModel.Day.used, .problems, .critical], id: \.self) { day in
                HStack(spacing: 3) {
                    HealthDayCell(day: day, size: 9)
                    Text(Self.legendName(day))
                }
            }
        }
        .lagoonFont(.caption2)
        .foregroundStyle(Lagoon.textTertiary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    static func legendName(_ day: HealthWidgetModel.Day) -> String {
        switch day {
        case .critical: return "Overcurrent or liquid"
        case .problems: return "Problems"
        case .used: return "Used"
        case .quiet: return "Quiet"
        }
    }
}

/// One day: an empty box when quiet, a filled one when used, the warning or
/// critical symbol when something went wrong. Shapes differ, so it reads
/// without colour.
struct HealthDayCell: View {
    let day: HealthWidgetModel.Day
    var size: CGFloat = HealthStrip.cell
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch day {
            case .quiet:
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    // Tertiary ink fades out once the system turns the widget monochrome.
                    .strokeBorder(renderingMode == .fullColor ? Lagoon.textTertiary : Lagoon.textSecondary,
                                  lineWidth: 1)
                    .padding(size * 0.1)
            case .used:
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(Lagoon.accent)
                    .padding(size * 0.1)
                    .widgetAccentable()
            case .problems:
                Image(systemName: Lagoon.severitySymbol(.warning))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Lagoon.warning)
            case .critical:
                Image(systemName: Lagoon.severitySymbol(.critical))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Lagoon.critical)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A `Link` to a page or port of the app, or just its content where links
/// are turned off: `ImageRenderer` draws a placeholder for a `Link`, so the
/// view tests turn them off.
struct HealthLink<Content: View>: View {
    let link: BusStopLink
    let content: Content
    @Environment(\.healthLinksEnabled) private var enabled

    init(_ link: BusStopLink, @ViewBuilder content: () -> Content) {
        self.link = link
        self.content = content()
    }

    var body: some View {
        if enabled {
            Link(destination: link.url) { content }
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    @Entry var healthLinksEnabled = true
}

/// A small heading over a group of rows.
struct HealthSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .lagoonFont(.caption, weight: .semibold)
            .foregroundStyle(Lagoon.textSecondary)
            .lineLimit(1)
    }
}
