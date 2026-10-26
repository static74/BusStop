import BusStopCore
import BusStopUI
import SwiftUI

/// Which events the timeline shows.
enum EventsFilter: Hashable {
    case all
    /// Warnings and critical findings, and links that got slower.
    case problems
    case kind(ConnectionEvent.Kind)

    func includes(_ event: ConnectionEvent) -> Bool {
        switch self {
        case .all: return true
        case .problems:
            if event.kind == .linkChanged { return event.isDowngrade }
            // Events saved before severities existed count as warnings.
            return event.kind == .diagnosticRaised && (event.severity ?? .warning) >= .warning
        case .kind(let kind): return event.kind == kind
        }
    }
}

/// Events from one calendar day.
struct EventDayGroup: Identifiable {
    var day: Date
    var events: [ConnectionEvent]
    var id: Date { day }

    /// The events that pass the filter and the search, by day, newest first.
    static func groups(_ events: [ConnectionEvent], filter: EventsFilter, query: String,
                       calendar: Calendar = .current) -> [EventDayGroup] {
        let filtered = events.filter { event in
            guard filter.includes(event) else { return false }
            guard !query.isEmpty else { return true }
            return event.title.localizedCaseInsensitiveContains(query)
                || event.detail.localizedCaseInsensitiveContains(query)
        }
        let byDay = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { day in
            EventDayGroup(day: day, events: (byDay[day] ?? []).sorted { $0.date > $1.date })
        }
    }
}

/// The last grouping, so the saved log (up to 5,000 events) is not grouped
/// again each time `body` runs, which is on every capture.
final class EventGroupCache {
    private struct Key: Equatable {
        var newestID: String?
        var count: Int
        var filter: EventsFilter
        var query: String
    }

    private var key: Key?
    private var groups: [EventDayGroup] = []

    func groups(_ events: [ConnectionEvent], filter: EventsFilter, query: String) -> [EventDayGroup] {
        let key = Key(newestID: events.first?.id, count: events.count, filter: filter, query: query)
        if key != self.key {
            self.key = key
            groups = EventDayGroup.groups(events, filter: filter, query: query)
        }
        return groups
    }
}

/// The Events page: a reverse-chronological timeline grouped by day, with a
/// kind filter and a Clear button. Clicking an event selects its device (or
/// port) and shows it in the inspector; the page stays on Events.
struct EventsDetailView: View {
    var store: PortStore
    var searchText: String
    /// Selects in the store and opens the inspector.
    var onSelect: (StoreSelection) -> Void

    @State private var filter: EventsFilter = .all
    /// The event last clicked, drawn as selected while it still points at the selection.
    @State private var selectedEventID: ConnectionEvent.ID?
    @State private var groupCache = EventGroupCache()

    var body: some View {
        let groups = groupCache.groups(store.events, filter: filter, query: TopologySearch.normalized(searchText))
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)

            if groups.isEmpty {
                WindowEmptyState(
                    systemName: "clock.arrow.circlepath",
                    title: store.events.isEmpty ? "No events yet" : "No matching events",
                    message: store.events.isEmpty
                        ? "Plug something in or unplug it. Connections, link changes and chargers appear here as they happen."
                        : "Try another filter or clear the search."
                )
            } else {
                timeline(groups)
            }
        }
    }

    /// The filter and Clear beside the title, or under it when one row does
    /// not fit beside the inspector, so the header never clips them.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            WindowDetailHeader(title: "Events", subtitle: subtitle) { controls }
            VStack(alignment: .leading, spacing: 10) {
                WindowDetailHeader(title: "Events", subtitle: subtitle)
                controls
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            filterMenu
            Button("Clear", role: .destructive) {
                withAnimation(.snappy) { store.clearEvents() }
            }
            .disabled(store.events.isEmpty)
            .help("Remove every event from the timeline and from saved history")
        }
    }

    private var subtitle: String {
        let count = WindowText.count(store.events.count, "event", "events")
        guard let oldest = store.events.last?.date else { return count }
        return count + " since " + oldest.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var filterMenu: some View {
        Picker("Show", selection: $filter) {
            Text("All events").tag(EventsFilter.all)
            Label("Problems", systemImage: "exclamationmark.triangle").tag(EventsFilter.problems)
            Divider()
            ForEach(ConnectionEvent.Kind.allCases, id: \.self) { kind in
                Label(WindowText.eventKind(kind), systemImage: WindowText.eventKindSymbol(kind))
                    .tag(EventsFilter.kind(kind))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Filter events by kind")
    }

    private func timeline(_ groups: [EventDayGroup]) -> some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: dayTitle(group.day), trailing: WindowText.count(group.events.count, "event", "events"))
                            VStack(spacing: 0) {
                                ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                    EventTimelineRow(
                                        event: event,
                                        now: context.date,
                                        isLast: index == group.events.count - 1,
                                        isSelected: isSelected(event),
                                        onSelect: { select(event) }
                                    )
                                }
                            }
                            .lagoonCard(padding: 0)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// Selects the event's device (or its port) and shows it in the inspector.
    private func select(_ event: ConnectionEvent) {
        guard let target = target(of: event) else { return }
        selectedEventID = event.id
        onSelect(target)
    }

    /// What clicking the event selects: the device while it is still
    /// connected, otherwise the port.
    private func target(of event: ConnectionEvent) -> StoreSelection? {
        let snapshot = store.snapshot
        if let id = event.deviceID, snapshot.device(id: id) != nil { return .device(id) }
        if let key = event.portKey, snapshot.port(key) != nil { return .port(key) }
        return nil
    }

    private func isSelected(_ event: ConnectionEvent) -> Bool {
        guard event.id == selectedEventID, let selection = store.selection else { return false }
        return target(of: event) == selection
    }
}

/// One event: kind symbol on a rail, title, detail, and absolute plus relative time.
struct EventTimelineRow: View {
    var event: ConnectionEvent
    var now: Date
    var isLast: Bool
    var isSelected: Bool = false
    var onSelect: () -> Void

    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                symbol
                EventTimelineText(event: event, now: now, relativeColor: WindowContrast.tertiary(contrast))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isHovered || isSelected ? Lagoon.surfaceRaised : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule().fill(Lagoon.accent).frame(width: 3).padding(.vertical, 8)
                }
            }
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(WindowContrast.stroke(contrast)).frame(height: 1).padding(.leading, 52)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityHint(event.deviceID != nil || event.portKey != nil ? "Shows details in the inspector" : "")
    }

    private var symbol: some View {
        let color = tint
        return Image(systemName: event.symbolName)
            .lagoonFont(size: 13, weight: .semibold)
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(Circle().fill(color.opacity(0.14)))
            .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 0.75))
            .accessibilityLabel(WindowText.eventKind(event.kind))
    }

    /// Turquoise for normal activity; amber only for slower links and diagnostics.
    private var tint: Color {
        switch event.kind {
        case .deviceConnected, .displayConnected: return Lagoon.accent
        case .deviceDisconnected, .displayDisconnected, .chargerDisconnected: return Lagoon.textSecondary
        case .linkChanged: return event.isDowngrade ? Lagoon.warning : Lagoon.accent
        case .chargerConnected: return Lagoon.powerIn
        case .diagnosticRaised: return Lagoon.warning
        }
    }
}

/// An event's title, detail and times. The times go under the title when the
/// title does not fit beside them on one line, so it wraps between words,
/// never inside one. The detail wraps either way.
struct EventTimelineText: View {
    var event: ConnectionEvent
    var now: Date
    var relativeColor: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                text
                VStack(alignment: .trailing, spacing: 3) { time; relativeTime }
            }
            stacked
        }
    }

    /// The times under the title and detail.
    var stacked: some View {
        VStack(alignment: .leading, spacing: 3) {
            text
            HStack(spacing: 6) { time; relativeTime }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.title)
                .lagoonFont(.callout, weight: .semibold)
                .foregroundStyle(Lagoon.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !event.detail.isEmpty {
                Text(event.detail)
                    .lagoonFont(.caption)
                    .foregroundStyle(Lagoon.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // No ideal width, so only the title decides where the times go.
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var time: some View {
        Text(event.date, format: .dateTime.hour().minute().second())
            .lagoonFont(.callout, monospacedDigits: true)
            .foregroundStyle(Lagoon.textPrimary)
    }

    private var relativeTime: some View {
        Text(Format.relative(event.date, now: now))
            .lagoonFont(.caption, monospacedDigits: true)
            .foregroundStyle(relativeColor)
    }
}
