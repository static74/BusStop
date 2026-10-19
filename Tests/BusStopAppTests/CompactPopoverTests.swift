import AppKit
import BusStopCore
import SwiftUI
import Testing
@testable import BusStopApp

/// The compact popover layout: rows fit the popover at every text size, the
/// list is shorter than the cards, and the row's summary text.
@MainActor
@Suite("Compact popover", .serialized)
struct CompactPopoverTests {
    /// A running demo store in a throwaway defaults suite, stopped and removed when `body` returns.
    private func withDemoStore(_ scenario: DemoScenario, _ name: String = #function,
                               configure: (AppSettings) -> Void = { _ in },
                               _ body: (PortStore) throws -> Void) rethrows {
        let suite = "BusStopAppTests.CompactPopover.\(name).\(scenario.rawValue)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.demoMode = true
        settings.demoScenario = scenario
        configure(settings)
        let store = PortStore(settings: settings)
        store.start()
        defer { store.stop() }
        try body(store)
    }

    /// Width `view` takes when offered `width`, as `PageWidthTests` measures pages.
    private func fittingWidth(_ view: some View, size: TextSizeSetting, width: CGFloat) -> CGFloat {
        NSHostingController(rootView: view.lagoonTextScale(size))
            .sizeThatFits(in: CGSize(width: width, height: 700)).width
    }

    private func fittingHeight(_ view: some View, width: CGFloat) -> CGFloat {
        NSHostingController(rootView: view.lagoonTextScale(.medium))
            .sizeThatFits(in: CGSize(width: width, height: 10_000)).height
    }

    @Test(arguments: TextSizeSetting.allCases)
    func compactRowsFitThePopover(_ size: TextSizeSetting) {
        // Rows sit inside the content's 12 pt padding and the card's 12 pt padding.
        let rowWidth = Lagoon.popoverWidth(for: size) - 48
        for scenario in [DemoScenario.dockStation, .studioDesk] {
            withDemoStore(scenario) { store in
                for port in store.snapshot.ports {
                    let width = fittingWidth(CompactPortRow(port: port, store: store), size: size, width: rowWidth)
                    #expect(width <= rowWidth + 1, "\(scenario) \(port.label.title)")
                }
            }
        }
        // The compact power strip carries its own card.
        let stripWidth = Lagoon.popoverWidth(for: size) - 24
        for scenario in DemoScenario.allCases {
            withDemoStore(scenario) { store in
                let width = fittingWidth(PowerStripView(store: store, isCompact: true), size: size, width: stripWidth)
                #expect(width <= stripWidth + 1, "\(scenario)")
            }
        }
    }

    @Test func compactRowWithPinAndRenameFieldFits() throws {
        let rowWidth = Lagoon.popoverWidth(for: .extraLarge) - 48
        try withDemoStore(.dockStation) { store in
            let port = try #require(store.snapshot.ports.first { $0.link != nil && $0.power != nil })
            store.pinPort(port.key)
            for isRenaming in [false, true] {
                let row = CompactPortRow(port: port, store: store, isRenaming: isRenaming)
                #expect(fittingWidth(row, size: .extraLarge, width: rowWidth) <= rowWidth + 1)
            }
        }
    }

    @Test func compactPortListIsShorterThanCards() {
        let width = Lagoon.popoverWidth(for: .medium) - 24
        withDemoStore(.dockStation) { store in
            let ports = store.visiblePorts
            let compact = fittingHeight(CompactPortList(ports: ports, store: store), width: width)
            let cards = fittingHeight(VStack(spacing: 8) {
                ForEach(ports) { PortCardView(port: $0, store: store) }
            }, width: width)
            #expect(compact > 0)
            #expect(compact < cards)
        }
    }

    @Test func emptyCompactListDrawsNoCard() {
        withDemoStore(.unplugged, configure: { $0.hideEmptyPorts = true }) { store in
            #expect(!store.snapshot.ports.isEmpty)
            #expect(store.visiblePorts.isEmpty)
            let height = fittingHeight(CompactPortList(ports: store.visiblePorts, store: store), width: 356)
            #expect(height == 0)
        }
    }

    @Test func compactSummaryNamesWhatIsConnected() {
        func port(connected: Bool = true, charger: ChargerInfo? = nil) -> PhysicalPort {
            PhysicalPort(key: PortKey(type: 2, number: 1), kind: .usbC, number: 1, registryName: "Port-USB-C@1",
                         label: PortLabel(location: "Left Rear", source: .catalog, connector: "USB-C", number: 1),
                         isConnected: connected, charger: charger)
        }
        func device(_ name: String, children: [DeviceNode] = []) -> DeviceNode {
            DeviceNode(id: "usb:\(name)", bus: .usb, kind: .storage, name: name, children: children)
        }
        let drive = device("Samsung T9")
        let hub = device("USB Hub", children: [device("Keyboard"), device("Mouse")])

        #expect(PopoverText.compactSummary(port(), devices: [drive]) == "Samsung T9")
        // Several trees count every level: the hub, its two devices and the drive.
        #expect(PopoverText.compactSummary(port(), devices: [hub, drive]) == "4 devices")
        #expect(PopoverText.compactSummary(port(charger: ChargerInfo(name: "96W USB-C Power Adapter")), devices: [])
                == "96W USB-C Power Adapter")
        #expect(PopoverText.compactSummary(port(), devices: []) == "Connected")
        #expect(PopoverText.compactSummary(port(connected: false), devices: []) == "Nothing connected")
        // A device that just left (a ghost) keeps its name while it is shown.
        #expect(PopoverText.compactSummary(port(connected: false), devices: [drive]) == "Samsung T9")
    }

    @Test func popoverLayoutPersistsAndResets() {
        let suite = "BusStopAppTests.CompactPopover.layout"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.popoverLayout == .cards)
        settings.popoverLayout = .compact

        let reread = AppSettings(defaults: defaults)
        #expect(reread.popoverLayout == .compact)
        reread.resetAll()
        #expect(reread.popoverLayout == .cards)
        #expect(AppSettings.Key.all.contains(AppSettings.Key.popoverLayout))
        #expect(AppSettings(defaults: defaults).popoverLayout == .cards)
    }
}
