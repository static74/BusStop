import AppKit
import Testing
@testable import BusStopApp

/// `PortStore` pauses power polling while nobody can see the menu bar. If wake
/// stopped clearing the pause, the power text would stay frozen.
@MainActor
@Suite("Polling pause")
struct PollingPauseTests {
    @Test(arguments: [
        (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
        (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification),
    ])
    func pausesUntilTheScreenIsBack(_ pause: Notification.Name, _ resume: Notification.Name) {
        let suite = "BusStopAppTests.PollingPause.\(pause.rawValue)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = PortStore(settings: AppSettings(defaults: UserDefaults(suiteName: suite)!))
        let center = NSWorkspace.shared.notificationCenter
        #expect(!store.isPollingPaused)
        // Observers use the main queue, so a post from the main thread runs them inline.
        center.post(name: pause, object: nil)
        #expect(store.isPollingPaused)
        center.post(name: resume, object: nil)
        #expect(!store.isPollingPaused)
    }
}
