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

    /// A hub with two children is pulled, then one child is plugged into
    /// the display's hub on another port while the hub's ghost still fades.
    /// The child shows once, live, and the hub's ghost keeps only the other.
    @Test(arguments: [("Keychron K8 Pro", "USB Optical Mouse"), ("USB Optical Mouse", "Keychron K8 Pro")])
    func aChildRepluggedElsewhereLeavesTheHubsGhost(_ moved: String, _ stayed: String) throws {
        let hub: Set = ["USB3.1 Hub", "USB2.1 Hub", "Keychron K8 Pro", "USB Optical Mouse"]
        var plugged = DemoScenario.studioDesk.raw(at: Date(), tick: 0)
        plugged.usbDevices.removeAll { $0.node.name == "DataTraveler 3.0" }
        var pulled = plugged
        pulled.usbDevices.removeAll { hub.contains($0.node.name) }
        var replugged = pulled
        var child = try #require(plugged.usbDevices.first { $0.node.name == moved })
        child.parentDeviceID = plugged.usbDevices.first { $0.node.name == "Studio Display XDR Camera" }?.parentDeviceID
        replugged.usbDevices.append(child)

        try withSettings("ghosts") { settings in
            let store = PortStore(settings: settings)
            store.ingest(plugged)
            store.ingest(pulled)
            let ghost = try #require(store.departing.first)
            #expect(store.departing.count == 1)
            #expect(Set(ghost.device.children.map(\.name)) == [moved, stayed])

            store.ingest(replugged)
            let shown = store.snapshot.ports.map(\.key).map(Optional.some) + [nil]
            let names = shown.flatMap { store.devicesWithGhosts(on: $0) }.flatMap { $0.flattened() }.map(\.device.name)
            #expect(names.filter { $0 == moved }.count == 1)
            #expect(store.departing.map(\.id) == [ghost.id])
            #expect(store.departing.first?.device.children.map(\.name) == [stayed])
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
