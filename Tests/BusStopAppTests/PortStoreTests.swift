import BusStopCore
import Foundation
import Testing
@testable import BusStopApp

/// `PortStore` keeping demo data apart from the real Mac's.
@MainActor
@Suite("Port store", .serialized)
struct PortStoreTests {
    /// Settings in a throwaway defaults suite, removed when `body` returns.
    private func withSettings(_ name: String, _ body: (AppSettings) throws -> Void) rethrows {
        let suite = "BusStopAppTests.PortStore.\(name)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: UserDefaults(suiteName: suite)!))
    }

    /// A running Studio desk demo store, stopped when `body` returns.
    private func withDemoStore(_ settings: AppSettings, _ body: (PortStore) throws -> Void) rethrows {
        settings.demoMode = true
        settings.demoScenario = .studioDesk
        let store = PortStore(settings: settings)
        store.start()
        defer { store.stop() }
        try body(store)
    }

    /// Demo scenarios use real model ids, so renaming or resetting a demo
    /// port must leave the real Mac's names alone, and the demo must not show them.
    @Test func demoPortNamesStayApartFromTheRealMacs() {
        withSettings("names") { settings in
            let model = DemoScenario.studioDesk.model
            let key = PortKey(type: PortKey.usbCType, number: 2)
            let liveKey = "\(model)#\(key)"
            settings.portNames = [liveKey: "Desk hub"]
            withDemoStore(settings) { store in
                #expect(store.snapshot.port(key)?.label.source == .catalog)
                store.renamePort(key, to: "Demo hub")
                #expect(settings.portNames == [liveKey: "Desk hub", "demo:\(liveKey)": "Demo hub"])
                #expect(store.snapshot.port(key)?.label.location == "Demo hub")
                store.resetPortNames()
                #expect(settings.portNames == [liveKey: "Desk hub"])
            }
        }
    }

    /// Demo mode was turned off, but the source switches a SwiftUI update
    /// later: a demo capture in between is still demo data.
    @Test func aDemoCaptureAfterTheToggleStaysDemo() {
        withSettings("toggle") { settings in
            withDemoStore(settings) { store in
                var notified: [ConnectionEvent] = []
                store.onEvents = { notified += $0 }
                settings.demoMode = false
                var raw = DemoScenario.studioDesk.raw(at: Date(), tick: 1)
                raw.usbDevices.removeAll { $0.node.name == "USB Optical Mouse" }
                store.ingest(raw)
                #expect(store.isDemo)
                #expect(store.snapshot.isDemo)
                #expect(!store.events.isEmpty)
                #expect(notified.isEmpty)
            }
        }
    }
}
