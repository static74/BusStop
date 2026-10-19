import BusStopCore
import Foundation
import Testing
@testable import BusStopApp

/// Which events notify, how a burst settles, and the per-finding cooldown.
@MainActor
@Suite("Notifications")
struct NotificationManagerTests {
    private let start = Date(timeIntervalSince1970: 1_791_115_200)

    private func finding(_ subject: String, severity: DiagnosticSeverity?) -> ConnectionEvent {
        ConnectionEvent(id: "diagnosticRaised:\(subject):1791115200000", date: start, kind: .diagnosticRaised,
                        title: "iPhone keeps disconnecting", detail: "", severity: severity, subjectID: subject)
    }

    private func withSettings(_ body: (AppSettings) -> Void) {
        let suite = "BusStopAppTests.Notifications.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        body(AppSettings(defaults: UserDefaults(suiteName: suite)!))
    }

    @Test func flakyWarningNotifiesUnderDiagnostics() {
        let event = finding("flakyConnection:usb:00100000:05ac:12a8", severity: .warning)
        #expect(NotificationManager.Family(event.kind) == .issues)
        #expect(NotificationManager.Family.issues.playsSound)
        withSettings { settings in
            #expect(NotificationManager.isEnabled(event, settings: settings, severity: .warning))
            settings.notifyDiagnostics = false
            #expect(!NotificationManager.isEnabled(event, settings: settings, severity: .warning))
        }
    }

    @Test func infoFindingsStayQuiet() {
        withSettings { settings in
            let event = finding("thunderboltBottleneck:tb:1", severity: .info)
            #expect(!NotificationManager.isEnabled(event, settings: settings, severity: .info))
        }
    }

    @Test func plugAndUnplugInOneBurstSettleToNothing() {
        let out = ConnectionEvent(id: "deviceDisconnected:usb:1:1791115200000", date: start, kind: .deviceDisconnected,
                                  title: "iPhone disconnected", detail: "", deviceID: "usb:1")
        let back = ConnectionEvent(id: "deviceConnected:usb:1:1791115202000", date: start.addingTimeInterval(2),
                                   kind: .deviceConnected, title: "iPhone connected", detail: "", deviceID: "usb:1")
        #expect(NotificationManager.settle([out, back]).isEmpty)
        #expect(NotificationManager.makeNotifications(for: [out, back]).isEmpty)
    }

    @Test func cooldownHoldsForThirtyMinutes() {
        let manager = NotificationManager()
        let event = finding("flakyConnection:usb:00100000:05ac:12a8", severity: .warning)
        #expect(!manager.isCoolingDown(event, now: start))
        #expect(manager.isCoolingDown(event, now: start.addingTimeInterval(29 * 60)))
        #expect(!manager.isCoolingDown(event, now: start.addingTimeInterval(31 * 60)))
        // Other findings have their own cooldown.
        #expect(!manager.isCoolingDown(finding("linkFlapping:usb:1", severity: .warning),
                                       now: start.addingTimeInterval(1)))
    }
}
