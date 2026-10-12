import BusStopCore
import Foundation
import UserNotifications

/// Posts local notifications for connection events (docs/SPEC.md §3.5).
///
/// Events are collected into bursts instead of being posted per capture. A
/// dock enumerates in stages over several seconds (its Thunderbolt switch,
/// then its USB controllers and the devices behind them, then the display),
/// so one plug-in spreads over several captures. A burst ends once
/// `quietWindow` passes without a new event, or `maxBurstDuration` after it
/// began. Its events are then posted as a few notifications: one for what
/// disconnected, one for what connected, and separate alerts for slower links
/// and new problems, which are the only ones that make a sound. A device that
/// comes and goes within one burst (a flaky cable) is not posted at all.
///
/// Delegate-free. All `UNUserNotificationCenter` work happens inside
/// `nonisolated` static helpers that create their own center reference and
/// exchange only `Sendable` values with the main actor, so no non-Sendable
/// UserNotifications object ever crosses an isolation boundary.
///
/// `UNUserNotificationCenter` requires a bundle identifier. A bare binary
/// started with `swift run` has none, so every method does nothing there.
final class NotificationManager {
    static let shared = NotificationManager()

    /// A burst ends once no new event has arrived for this many seconds.
    static let quietWindow: TimeInterval = 2
    /// A burst is posted at most this many seconds after its first event,
    /// even if events keep arriving.
    static let maxBurstDuration: TimeInterval = 6
    /// More than this many events of one family in a burst become one
    /// grouped notification, so a dock with ten devices does not post ten.
    static let groupingThreshold = 2

    /// Events of the current burst, oldest first.
    private var pending: [ConnectionEvent] = []
    /// When each diagnostic last raised an alert, keyed by its subject. A
    /// finding that clears and comes back (a flaky cable, a charger hold that
    /// toggles) alerts at most once per `diagnosticCooldown`.
    private var lastDiagnosticAlert: [String: Date] = [:]
    static let diagnosticCooldown: TimeInterval = 30 * 60
    private var burstStart: Date?
    private var flushTask: Task<Void, Never>?

    /// False when running outside an app bundle.
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// Asks for permission if not yet determined. Returns whether alerts are allowed.
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        return await Self.requestAuthorizationIfNeeded()
    }

    /// "Allowed", "Denied", "Not requested".
    func authorizationStatusDescription() async -> String {
        guard isAvailable else { return "Unavailable outside the app bundle" }
        switch await Self.currentAuthorization() {
        case .allowed: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested"
        }
    }

    /// Adds the events the user opted into to the current burst; they are
    /// posted when the burst ends.
    ///
    /// `diagnostics` are the findings of the snapshot the events came from.
    /// They give each new finding its severity: only warnings and critical
    /// findings notify, the same ones the popover banner shows. Info findings
    /// stay in the event log only.
    func post(_ events: [ConnectionEvent], settings: AppSettings, diagnostics: [Diagnostic] = []) {
        guard isAvailable, !events.isEmpty else { return }
        let now = Date()
        let wanted = events.filter { event in
            let severity = event.severity ?? Self.severity(of: event, in: diagnostics)
            guard Self.isEnabled(event, settings: settings, severity: severity) else { return false }
            return !isCoolingDown(event, now: now)
        }
        guard !wanted.isEmpty else { return }

        pending += wanted
        let start = burstStart ?? now
        burstStart = start
        let deadline = min(now.addingTimeInterval(Self.quietWindow),
                           start.addingTimeInterval(Self.maxBurstDuration))
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Ends the current burst and posts its notifications.
    func flush() {
        let events = pending
        pending = []
        burstStart = nil
        flushTask?.cancel()
        flushTask = nil
        let notifications = Self.makeNotifications(for: events)
        guard !notifications.isEmpty else { return }
        Task {
            await Self.deliver(notifications)
        }
    }

    // MARK: Filtering

    /// Whether the user's toggles allow a notification for this event.
    /// A new finding notifies only when it is a warning or worse; pass its
    /// `severity` when known (unknown counts as a warning).
    /// True for a diagnostic that already alerted within the cooldown.
    /// Records the alert time otherwise.
    private func isCoolingDown(_ event: ConnectionEvent, now: Date) -> Bool {
        guard event.kind == .diagnosticRaised else { return false }
        let subject = event.subjectID ?? event.title
        if let last = lastDiagnosticAlert[subject], now.timeIntervalSince(last) < Self.diagnosticCooldown {
            return true
        }
        lastDiagnosticAlert[subject] = now
        return false
    }

    static func isEnabled(_ event: ConnectionEvent, settings: AppSettings,
                          severity: DiagnosticSeverity? = nil) -> Bool {
        switch event.kind {
        case .deviceConnected, .displayConnected: return settings.notifyConnect
        case .deviceDisconnected, .displayDisconnected: return settings.notifyDisconnect
        case .linkChanged: return event.isDowngrade && settings.notifyDowngrade
        case .chargerConnected, .chargerDisconnected: return settings.notifyCharger
        case .diagnosticRaised: return settings.notifyDiagnostics && (severity ?? .warning) >= .warning
        }
    }

    /// The severity of the finding behind a `.diagnosticRaised` event, looked
    /// up in `diagnostics` by finding id, or else by title and detail. Nil for
    /// other events and for findings that are not in the list.
    static func severity(of event: ConnectionEvent, in diagnostics: [Diagnostic]) -> DiagnosticSeverity? {
        guard event.kind == .diagnosticRaised else { return nil }
        if let id = subject(of: event), let match = diagnostics.first(where: { $0.id == id }) {
            return match.severity
        }
        return diagnostics.first { $0.title == event.title && $0.detail == event.detail }?.severity
    }

    /// The subject inside an event id of the form
    /// `"<kind>:<subject>:<milliseconds>"`: a device id, a display id, a
    /// finding id or `"charger"`. Subjects can contain colons themselves.
    static func subject(of event: ConnectionEvent) -> String? {
        let prefix = event.kind.rawValue + ":"
        guard event.id.hasPrefix(prefix), let lastColon = event.id.lastIndex(of: ":") else { return nil }
        let start = event.id.index(event.id.startIndex, offsetBy: prefix.count)
        guard start < lastColon else { return nil }
        return String(event.id[start..<lastColon])
    }

    // MARK: Grouping

    /// Kinds of events that share one grouped notification, in posting order.
    enum Family: String {
        /// Devices, displays and chargers that went away.
        case departures
        /// Devices, displays and chargers that arrived.
        case arrivals
        /// Links that got slower.
        case slowdowns
        /// New warnings and critical findings.
        case issues

        static let postingOrder: [Family] = [.departures, .arrivals, .slowdowns, .issues]

        init(_ kind: ConnectionEvent.Kind) {
            switch kind {
            case .deviceDisconnected, .displayDisconnected, .chargerDisconnected: self = .departures
            case .deviceConnected, .displayConnected, .chargerConnected: self = .arrivals
            case .linkChanged: self = .slowdowns
            case .diagnosticRaised: self = .issues
            }
        }

        /// Plug and unplug alerts stay quiet; problems make a sound.
        var playsSound: Bool {
            self == .slowdowns || self == .issues
        }

        var threadIdentifier: String { "busstop.\(rawValue)" }
    }

    /// Turns one burst into notifications. After `settle(_:)`, each family is
    /// posted as one notification per event, or as one grouped notification
    /// when `shouldGroup(_:family:)` says so.
    static func makeNotifications(for events: [ConnectionEvent]) -> [PendingNotification] {
        let settled = settle(events)
        var result: [PendingNotification] = []
        for family in Family.postingOrder {
            let group = settled.filter { Family($0.kind) == family }
            guard !group.isEmpty else { continue }
            if shouldGroup(group, family: family) {
                result.append(groupedNotification(family: family, events: group))
            } else {
                result += group.map { event in
                    PendingNotification(identifier: "busstop.\(event.id)", title: event.title, body: event.detail,
                                        threadIdentifier: family.threadIdentifier, playsSound: family.playsSound)
                }
            }
        }
        return result
    }

    /// Drops what cancels out within a burst. When a device, display or
    /// charger has events pointing both ways and ends where it started
    /// (connected then disconnected, or the reverse), nothing changed, so
    /// nothing is posted. Otherwise only its latest event is kept, as for a
    /// repeated slowdown or finding.
    static func settle(_ events: [ConnectionEvent]) -> [ConnectionEvent] {
        var positions: [String: [Int]] = [:]
        for (index, event) in events.enumerated() {
            positions[settleKey(event), default: []].append(index)
        }
        var kept = Set<Int>()
        for indexes in positions.values {
            guard let first = indexes.first, let last = indexes.last else { continue }
            let firstFamily = Family(events[first].kind)
            let lastFamily = Family(events[last].kind)
            let isPresence = firstFamily == .arrivals || firstFamily == .departures
            if isPresence && firstFamily != lastFamily { continue }
            kept.insert(last)
        }
        return events.indices.filter { kept.contains($0) }.map { events[$0] }
    }

    /// Events with the same key describe the same thing.
    private static func settleKey(_ event: ConnectionEvent) -> String {
        switch event.kind {
        case .deviceConnected, .deviceDisconnected:
            return "device:" + (event.deviceID ?? subject(of: event) ?? event.id)
        case .displayConnected, .displayDisconnected:
            return "display:" + (subject(of: event) ?? event.id)
        case .chargerConnected, .chargerDisconnected:
            return "charger:" + (subject(of: event) ?? event.id)
        case .linkChanged:
            return "link:" + (event.deviceID ?? subject(of: event) ?? event.id)
        case .diagnosticRaised:
            // Several findings can name one device, so use the finding id.
            return "issue:" + (subject(of: event) ?? event.id)
        }
    }

    /// Departures and arrivals are grouped when there are more than
    /// `groupingThreshold` of them, or two on the same port (a dock and its
    /// display) or two on no known port. Slowdowns and findings are grouped
    /// only when there are more than `groupingThreshold`, since each one
    /// carries advice of its own.
    static func shouldGroup(_ events: [ConnectionEvent], family: Family) -> Bool {
        if events.count > groupingThreshold { return true }
        guard events.count == 2, family == .arrivals || family == .departures else { return false }
        return events[0].portKey == events[1].portKey
    }

    private static func groupedNotification(family: Family, events: [ConnectionEvent]) -> PendingNotification {
        let title: String
        let body: String
        switch family {
        case .departures, .arrivals:
            let verb = family == .arrivals ? "connected" : "disconnected"
            let lead = leadIndex(events)
            var others = events.map { subjectName(of: $0) }
            let leadName = others.remove(at: lead)
            title = "\(leadName) and \(others.count) more \(verb)"
            body = events[lead].detail + "\nAlso \(verb): " + listText(others)
        case .slowdowns:
            title = "\(events.count) links slowed down"
            body = listText(events.map { subjectName(of: $0) })
        case .issues:
            title = "\(events.count) new issues found"
            body = listText(events.map(\.title))
        }
        // Unique, so two groups never replace each other.
        let identifier = "busstop.group.\(family.rawValue).\(UUID().uuidString)"
        return PendingNotification(identifier: identifier, title: title, body: body,
                                   threadIdentifier: family.threadIdentifier, playsSound: family.playsSound)
    }

    /// The event that names a group: the first device that brought others
    /// with it (a dock or hub), else the first device, else the first event.
    private static func leadIndex(_ events: [ConnectionEvent]) -> Int {
        let deviceKinds: Set<ConnectionEvent.Kind> = [.deviceConnected, .deviceDisconnected]
        if let index = events.firstIndex(where: { deviceKinds.contains($0.kind) && $0.detail.contains(" more device") }) {
            return index
        }
        return events.firstIndex { deviceKinds.contains($0.kind) } ?? 0
    }

    /// "A, B, C" or "A, B, C, D, E, F and 3 more".
    static func listText(_ names: [String], limit: Int = 6) -> String {
        let shown = names.prefix(limit).joined(separator: ", ")
        return names.count > limit ? "\(shown) and \(names.count - limit) more" : shown
    }

    /// The device or display name inside an event title such as
    /// "Samsung T9 connected"; the whole title when there is no known suffix.
    static func subjectName(of event: ConnectionEvent) -> String {
        let suffixes = [" connected", " disconnected", " slowed down", " sped up", " reconnected"]
        for suffix in suffixes where event.title.hasSuffix(suffix) && event.title.count > suffix.count {
            return String(event.title.dropLast(suffix.count))
        }
        return event.title
    }

    // MARK: UserNotifications (off the main actor)

    /// Authorization state reduced to a Sendable value.
    nonisolated enum Authorization: Sendable {
        case allowed
        case denied
        case notDetermined
    }

    nonisolated private static func currentAuthorization() async -> Authorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    nonisolated private static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        case .denied:
            return false
        default:
            return true
        }
    }

    nonisolated private static func deliver(_ notifications: [PendingNotification]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            break
        default:
            return
        }
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.threadIdentifier = notification.threadIdentifier
            if notification.playsSound {
                content.sound = .default
            }
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

/// A notification ready to post. Plain Sendable data, built on the main actor
/// and handed to the UserNotifications helpers.
nonisolated struct PendingNotification: Sendable, Hashable {
    var identifier: String
    var title: String
    var body: String
    var threadIdentifier: String
    var playsSound: Bool
}
