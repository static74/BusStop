import BusStopCore
import Foundation
import UserNotifications

/// Posts local notifications for connection events (docs/SPEC.md §3.5).
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

    /// More than this many events of one kind in a single refresh become one
    /// grouped notification, so a dock with ten devices does not post ten.
    static let groupingThreshold = 3

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

    /// Posts notifications for the events the user opted into.
    func post(_ events: [ConnectionEvent], settings: AppSettings) {
        guard isAvailable, !events.isEmpty else { return }
        let wanted = events.filter { Self.isEnabled($0, settings: settings) }
        let notifications = Self.makeNotifications(for: wanted)
        guard !notifications.isEmpty else { return }
        Task {
            await Self.deliver(notifications)
        }
    }

    // MARK: Filtering and grouping

    /// Whether the user's toggles allow a notification for this event.
    static func isEnabled(_ event: ConnectionEvent, settings: AppSettings) -> Bool {
        switch event.kind {
        case .deviceConnected, .displayConnected: return settings.notifyConnect
        case .deviceDisconnected, .displayDisconnected: return settings.notifyDisconnect
        case .linkChanged: return event.isDowngrade && settings.notifyDowngrade
        case .chargerConnected, .chargerDisconnected: return settings.notifyCharger
        case .diagnosticRaised: return settings.notifyDiagnostics
        }
    }

    /// One notification per event, except that kinds with more than
    /// `groupingThreshold` events collapse into one grouped notification.
    static func makeNotifications(for events: [ConnectionEvent]) -> [PendingNotification] {
        var result: [PendingNotification] = []
        // Keep the order in which each kind first appears.
        var kinds: [ConnectionEvent.Kind] = []
        var byKind: [ConnectionEvent.Kind: [ConnectionEvent]] = [:]
        for event in events {
            if byKind[event.kind] == nil { kinds.append(event.kind) }
            byKind[event.kind, default: []].append(event)
        }
        for kind in kinds {
            let group = byKind[kind] ?? []
            if group.count > groupingThreshold {
                result.append(groupedNotification(kind: kind, events: group))
            } else {
                result += group.map { event in
                    PendingNotification(identifier: "busstop.\(event.id)", title: event.title, body: event.detail,
                                        threadIdentifier: threadIdentifier(kind), playsSound: playsSound(kind))
                }
            }
        }
        return result
    }

    private static func groupedNotification(kind: ConnectionEvent.Kind, events: [ConnectionEvent]) -> PendingNotification {
        let count = events.count
        let title: String
        switch kind {
        case .deviceConnected: title = "\(count) devices connected"
        case .deviceDisconnected: title = "\(count) devices disconnected"
        case .displayConnected: title = "\(count) displays connected"
        case .displayDisconnected: title = "\(count) displays disconnected"
        case .linkChanged: title = "\(count) links slowed down"
        case .chargerConnected, .chargerDisconnected: title = "\(count) charger changes"
        case .diagnosticRaised: title = "\(count) new issues found"
        }
        let names = events.map { subjectName(of: $0) }
        let shown = names.prefix(6).joined(separator: ", ")
        let body = names.count > 6 ? "\(shown) and \(names.count - 6) more" : shown
        let stamp = Int((events.first?.date ?? Date()).timeIntervalSince1970)
        return PendingNotification(identifier: "busstop.group.\(kind.rawValue).\(stamp)", title: title, body: body,
                                   threadIdentifier: threadIdentifier(kind), playsSound: playsSound(kind))
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

    private static func threadIdentifier(_ kind: ConnectionEvent.Kind) -> String {
        "busstop.\(kind.rawValue)"
    }

    /// Plug and unplug alerts stay quiet; problems make a sound.
    private static func playsSound(_ kind: ConnectionEvent.Kind) -> Bool {
        switch kind {
        case .linkChanged, .diagnosticRaised: return true
        default: return false
        }
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
