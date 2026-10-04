import BusStopCore
import Foundation

/// Posts local notifications for connection events. Placeholder; implemented
/// by the app shell.
final class NotificationManager {
    static let shared = NotificationManager()

    /// Asks for permission if not yet determined. Returns whether alerts are allowed.
    func requestAuthorization() async -> Bool { false }

    /// "Allowed", "Denied", "Not requested".
    func authorizationStatusDescription() async -> String { "Not requested" }

    /// Posts notifications for the events the user opted into.
    func post(_ events: [ConnectionEvent], settings: AppSettings) {}
}
