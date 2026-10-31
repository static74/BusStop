import AppKit
import BusStopCore
import BusStopUI
import SwiftUI
import Testing
@testable import BusStopApp

@Suite("Map power bubbles")
struct GraphPowerTests {
    @Test func tiersStepAtFiveFifteenAndFortyFiveWatts() {
        #expect([0, 1, 4_999, 5_000, 14_999, 15_000, 44_999, 45_000, 140_000].map(PowerTier.init(milliwatts:))
                == [.none, .under5, .under5, .under15, .under15, .under45, .under45, .high, .high])
    }

    @Test func budgetsAreMarkedAsCeilings() {
        #expect(GraphEdgePower(milliwatts: 47_000, flowsToParent: true, isMeasured: true).label == "47 W")
        #expect(GraphEdgePower(milliwatts: 4_500, flowsToParent: false, isMeasured: false).label.hasPrefix("≤"))
    }

    /// A power bubble hangs under its speed chip, so in one column each
    /// chip's point needs half a speed chip, the gap and a power chip of room
    /// below it before the next speed chip's top half, at every text size, in
    /// every demo setup and under a hub with 15 devices, whose links fan out
    /// from the hub's card closest together. Pairs should also stay clearly
    /// further apart than a speed chip is from its own power chip.
    @Test @MainActor func stackedChipsNeverOverlap() {
        let link = LinkInfo(family: .usb, generation: "USB 3.2 Gen 2", bitsPerSecond: 10_000_000_000)
        var inputs: [(String, GraphInput)] = []
        for scenario in DemoScenario.allCases {
            let suite = "BusStopAppTests.StackedChips.\(scenario.rawValue)"
            defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.demoMode = true
            settings.demoScenario = scenario
            let store = PortStore(settings: settings)
            store.start()
            defer { store.stop() }
            let snapshot = store.snapshot
            inputs.append((scenario.rawValue, GraphInput(
                ports: snapshot.ports, portDisplays: TopologyExtras.portDisplays(in: snapshot, ports: snapshot.ports))))
        }
        let leaves = (1...15).map { DeviceNode(id: "usb:\($0)", bus: .usb, kind: .storage, name: "Drive \($0)", link: link) }
        let hub = DeviceNode(id: "usb:hub", bus: .usb, kind: .hub, name: "Hub", link: link, children: leaves)
        inputs.append(("15-device hub", GraphInput(ports: [PhysicalPort(
            key: PortKey(type: PortKey.usbCType, number: 1), kind: .usbC, number: 1, registryName: "Port-USB-C@1",
            label: PortLabel(location: "Left Front", source: .catalog, connector: "USB-C", number: 1),
            isConnected: true, link: link, devices: [hub])])))

        var compared = 0
        for (name, input) in inputs {
            for size in TextSizeSetting.allCases {
                let speed = NSHostingView(rootView: SpeedChip(link: link).environment(\.lagoonTextScale, size.scale))
                    .fittingSize.height
                let power = NSHostingView(rootView: PowerChip(power: GraphEdgePower(
                    milliwatts: 4_500, flowsToParent: false, isMeasured: false)).environment(\.lagoonTextScale, size.scale))
                    .fittingSize.height
                let stack = speed + GraphChipsLayer.stackSpacing + power
                let layout = GraphLayout.make(input, metrics: GraphMetrics.standard.scaled(by: size.scale))
                let points = layout.edges.compactMap { $0.link == nil ? nil : $0.chipPoint }
                for column in Dictionary(grouping: points, by: { $0.x.rounded() }).values {
                    let ys = column.map(\.y).sorted()
                    for (upper, lower) in zip(ys, ys.dropFirst()) {
                        compared += 1
                        #expect(lower - upper - stack >= 3 * GraphChipsLayer.stackSpacing,
                                "\(name) at \(size): chips \(lower - upper) pt apart, stack \(stack) pt")
                    }
                }
            }
        }
        // The inputs include sibling links, so the check is not vacuous.
        #expect(compared > 0)
    }
}
