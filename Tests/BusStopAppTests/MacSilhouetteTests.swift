import AppKit
import BusStopCore
import Foundation
import SwiftUI
import Testing
@testable import BusStopApp

/// The Mac Outline page: how a port is coloured, which page a reveal lands
/// on, and the `topology:<page>` Automation names.
@MainActor
@Suite("Mac Outline")
struct MacSilhouetteTests {
    private func port(isConnected: Bool = true, link: LinkInfo? = nil, power: PortPower? = nil,
                      charger: ChargerInfo? = nil, kind: PortKind = .usbC) -> PhysicalPort {
        PhysicalPort(
            key: PortKey(type: PortKey.usbCType, number: 1), kind: kind, number: 1, registryName: "Port-USB-C@1",
            label: PortLabel(location: "Left Front", source: .catalog, connector: "USB-C", number: 1),
            isConnected: isConnected, link: link, power: power, charger: charger)
    }

    @Test func dataPaint() {
        #expect(SilhouettePaint.paint(for: port(isConnected: false)) == .empty)
        let tenGigabit = LinkInfo(family: .usb, generation: "USB 3.2 Gen 2", bitsPerSecond: 10_000_000_000)
        #expect(SilhouettePaint.paint(for: port(link: tenGigabit)) == .link(.gbps10))
        let hdmi = LinkInfo(family: .hdmi, generation: "HDMI")
        #expect(SilhouettePaint.paint(for: port(link: hdmi, kind: .hdmi)) == .noRate)
        let charger = ChargerInfo(name: "96W USB-C Power Adapter", ratedWatts: 96)
        #expect(SilhouettePaint.paint(for: port(charger: charger)) == .charger)
    }

    @Test func powerBubbleReadsThePort() throws {
        let charging = port(power: PortPower(direction: .input, milliwatts: 60_000, source: .smc),
                            charger: ChargerInfo(name: "96W USB-C Power Adapter", ratedWatts: 96))
        let power = try #require(GraphPaint.portPower(charging))
        #expect(power.label == "60 W" && power.flowsToParent && power.tier == .high)
        #expect(GraphPaint.portPower(port(isConnected: false)) == nil)
    }

    private func demoStore(_ scenario: DemoScenario, suite: String) -> PortStore {
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.demoMode = true
        settings.demoScenario = scenario
        let store = PortStore(settings: settings)
        store.start()
        return store
    }

    @Test func revealStaysOnSilhouette() throws {
        let suite = "BusStopAppTests.SilhouetteReveal"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = demoStore(.studioDesk, suite: suite)
        defer { store.stop() }
        let snapshot = store.snapshot

        let device = try #require(snapshot.ports.first { !$0.devices.isEmpty }?.devices.first)
        #expect(TopologyWindowView.page(revealing: .device(device.id), from: .silhouette, store: store) == .silhouette)
        #expect(TopologyWindowView.page(revealing: .host, from: .silhouette, store: store) == .silhouette)
        // The built-in display is on no port, so the Overview shows it.
        let builtIn = try #require(snapshot.displays.first { $0.portKey == nil })
        #expect(TopologyWindowView.page(revealing: .display(builtIn.id), from: .silhouette, store: store) == .overview)
    }

    /// A search keeps a port bright when its monitor matches, also when macOS
    /// lists that monitor only as a display, and the tooltip names it.
    @Test func searchMatchesDisplayOnPort() throws {
        let suite = "BusStopAppTests.SilhouetteSearch"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = demoStore(.dockStation, suite: suite)
        defer { store.stop() }
        var snapshot = store.snapshot
        let index = try #require(snapshot.ports.firstIndex { $0.key.type == PortKey.hdmiType })
        #expect(MacSilhouetteView.matches(snapshot.ports[index], in: snapshot, query: "LG UltraFine"))
        #expect(!MacSilhouetteView.matches(snapshot.ports[index], in: snapshot, query: "zzz"))
        // The display-only case: no device node under the port.
        snapshot.ports[index].devices = []
        let hdmi = snapshot.ports[index]
        #expect(MacSilhouetteView.matches(hdmi, in: snapshot, query: "LG UltraFine"))
        #expect(MacSilhouetteView.help(hdmi, in: snapshot).contains("LG UltraFine"))
    }

    @Test func automationPageNames() {
        #expect(TopologySidebarItem(automationName: "silhouette") == .silhouette)
        #expect(TopologySidebarItem(automationName: "events") == .events)
        #expect(TopologySidebarItem(automationName: "allPorts") == .allPorts)
        #expect(TopologySidebarItem(automationName: "bogus") == nil)
    }

    /// At its narrowest the outline keeps neighbouring port buttons apart,
    /// so a click never lands on the next port, on every catalogued Mac.
    @Test func slotsStayAButtonApart() throws {
        for model in PortLocationCatalog.allModels {
            let entry = try #require(PortLocationCatalog.entry(for: model))
            let machine = MachineSummary(model: model, name: entry.marketingName, osVersion: "27.0", isLaptop: false)
            // With no live ports every catalogue row becomes a slot.
            let layout = ChassisLayout.resolve(machine: machine, ports: [])
            let shape = ChassisShape(family: layout.family)
            let groups: [[ChassisFace]] = layout.family == .laptop ? [[.left, .right]] : [[.front], [.rear]]
            for faces in groups {
                let slots = layout.slots.filter { faces.contains($0.face) }
                let width = shape.minWidth(for: slots)
                let rect = CGRect(x: 0, y: 0, width: width, height: width / shape.aspectRatio)
                for face in faces {
                    let points = slots.filter { $0.face == face }.map { shape.point(for: $0, in: rect) }
                    for (a, b) in zip(points, points.dropFirst()) {
                        #expect(hypot(b.x - a.x, b.y - a.y) >= ChassisShape.slotSpacing - 0.01, "\(model) \(face)")
                    }
                }
            }
        }
    }

    /// Every demo port has a place on the outline's drawn faces, so none
    /// falls into "Not placed".
    @Test(arguments: DemoScenario.allCases)
    func demoPortsAreAllDrawn(_ scenario: DemoScenario) {
        let suite = "BusStopAppTests.SilhouetteFaces.\(scenario.rawValue)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = demoStore(scenario, suite: suite)
        defer { store.stop() }
        let layout = ChassisLayout.resolve(machine: store.snapshot.machine, ports: store.snapshot.ports)
        let faces = MacSilhouetteView.faces(for: layout)
        #expect(layout.unplaced.isEmpty)
        #expect(layout.slots.allSatisfy { faces.contains($0.face) })
    }

    /// Each face sits in its own hosting view, so a stalled tooltip tracker
    /// on the page cannot silence the ports (docs/decisions.md, "The map's
    /// controls get their own hosting views"), and the host takes the face's
    /// size rather than its content's fitting size.
    @Test(arguments: [DemoScenario.studioDesk, .dockStation])
    func eachFaceHasItsOwnHostingView(_ scenario: DemoScenario) throws {
        let suite = "BusStopAppTests.SilhouetteHosts.\(scenario.rawValue)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = demoStore(scenario, suite: suite)
        defer { store.stop() }
        let page = NSHostingView(rootView: MacSilhouettePage(store: store, searchText: "", onSelect: { _ in }))
        page.frame = CGRect(x: 0, y: 0, width: 900, height: 900)
        let window = NSWindow(contentRect: page.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = page
        defer { window.close() }
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            page.layoutSubtreeIfNeeded()
        }

        func hosts(in view: NSView) -> [GraphControlHostingView] {
            view.subviews.flatMap { ($0 as? GraphControlHostingView).map { [$0] } ?? hosts(in: $0) }
        }
        let layout = ChassisLayout.resolve(machine: store.snapshot.machine, ports: store.snapshot.ports)
        let shape = ChassisShape(family: layout.family)
        // The Data/Power picker is hosted too, at its own small size.
        let faces = hosts(in: page).filter { $0.frame.width > 200 }
        #expect(faces.count == (layout.family == .laptop ? 1 : MacSilhouetteView.faces(for: layout).count))
        for face in faces {
            #expect(abs(face.frame.width / face.frame.height - shape.aspectRatio) < 0.02, "\(face.frame)")
        }
    }
}
