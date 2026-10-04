import BusStopCore
import SwiftUI

/// Which events the timeline shows.
enum EventsFilter: Hashable {
    case all
    case kind(ConnectionEvent.Kind)
}

/// Events from one calendar day.
struct EventDayGroup: Identifiable {
    var day: Date
    var events: [ConnectionEvent]
    var id: Date { day }
}

/// The Events page: a reverse-chronological timeline grouped by day, with a
/// kind filter and a Clear button.
struct EventsDetailView: View {
    var store: PortStore
    var searchText: String

    @State private var filter: EventsFilter = .all

    var body: some View {
        let groups = makeGroups()
        VStack(alignment: .leading, spacing: 14) {
            WindowDetailHeader(title: "Events", subtitle: subtitle) {
                HStack(spacing: 10) {
                    filterMenu
                    Button("Clear", role: .destructive) {
                        withAnimation(.snappy) { store.clearEvents() }
                    }
                    .disabled(store.events.isEmpty)
                    .help("Remove every event from the timeline")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if groups.isEmpty {
                EmptyStateView(
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

    private var subtitle: String {
        WindowText.count(store.events.count, "event", "events") + " since Bus Stop started"
    }

    private var filterMenu: some View {
        Picker("Show", selection: $filter) {
            Text("All events").tag(EventsFilter.all)
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

    private func makeGroups() -> [EventDayGroup] {
        let query = TopologySearch.normalized(searchText)
        let filtered = store.events.filter { event in
            if case .kind(let kind) = filter, event.kind != kind { return false }
            guard !query.isEmpty else { return true }
            return event.title.localizedCaseInsensitiveContains(query)
                || event.detail.localizedCaseInsensitiveContains(query)
        }
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { day in
            EventDayGroup(day: day, events: (byDay[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// Selects the event's device (or its port) in the inspector.
    private func select(_ event: ConnectionEvent) {
        let snapshot = store.snapshot
        if let id = event.deviceID, snapshot.device(id: id) != nil {
            store.selection = .device(id)
        } else if let key = event.portKey, snapshot.port(key) != nil {
            store.selection = .port(key)
        }
    }
}

/// One event: kind symbol on a rail, title, detail, and absolute plus relative time.
struct EventTimelineRow: View {
    var event: ConnectionEvent
    var now: Date
    var isLast: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                symbol
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(.callout).weight(.semibold))
                        .foregroundStyle(Lagoon.textPrimary)
                    if !event.detail.isEmpty {
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(Lagoon.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(event.date, format: .dateTime.hour().minute().second())
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textPrimary)
                    Text(Format.relative(event.date, now: now))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isHovered ? Lagoon.surfaceRaised : Color.clear)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(Lagoon.stroke).frame(height: 1).padding(.leading, 52)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(event.deviceID != nil || event.portKey != nil ? "Shows details in the inspector" : "")
    }

    private var symbol: some View {
        let color = tint
        return Image(systemName: event.symbolName)
            .font(.system(size: 13, weight: .semibold))
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
