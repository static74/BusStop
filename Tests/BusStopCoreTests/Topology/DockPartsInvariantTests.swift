import Foundation
import Testing
@testable import BusStopCore

/// Safety properties of folding the built-in parts of docks and hubs
/// (`DockParts`, `HubChips`), checked on every demo scenario, the real Anker,
/// Dell and Mac mini captures and the robustness inputs: nothing is lost or
/// drawn twice, every part hangs off its holder or another part, no part is
/// a device someone plugged in, and `DeviceNode.unfolded()` gives back the
/// tree as it was.
@Suite("Topology: built-in dock part invariants")
struct DockPartsInvariantTests {
    /// A device's identity that survives `makeDeviceIDsUnique`: device IDs
    /// can repeat in odd captures and then get suffixes in a different order
    /// with and without folding, registry IDs cannot (one per bus).
    static func key(_ node: DeviceNode) -> String {
        node.registryID.map { "\(node.bus.rawValue):\($0)" } ?? node.id
    }

    /// The tree by `key`, children in key order.
    static func shape(_ node: DeviceNode) -> String {
        key(node) + "(" + node.children.map(shape).sorted().joined(separator: ",") + ")"
    }

    static func check(_ raw: RawSnapshot, sourceLocation: SourceLocation = #_sourceLocation) {
        let folded = TopologyBuilder.build(raw, options: BuildOptions(), foldsDockParts: true)
        let unfolded = TopologyBuilder.build(raw, options: BuildOptions(), foldsDockParts: false)

        let visible = folded.allDevices.map { key($0.device) }
        let docks = folded.allDevices.map(\.device).filter { $0.internalParts != nil }
        let parts = docks.flatMap { $0.internalParts ?? [] }.map(key)
        let before = unfolded.allDevices.map { key($0.device) }
        #expect(Set(visible).isDisjoint(with: parts), sourceLocation: sourceLocation)
        #expect((visible + parts).sorted() == before.sorted(), sourceLocation: sourceLocation)

        // Where each device hung before folding.
        var parentOf: [String: String] = [:]
        for entry in unfolded.allDevices {
            for child in entry.device.children { parentOf[key(child)] = key(entry.device) }
        }
        for dock in docks {
            let dockParts = dock.internalParts ?? []
            let partKeys = Set(dockParts.map(key))
            // `internalParentID` holds a part's device ID.
            let keyOfPart = Dictionary(dockParts.map { ($0.id, key($0)) }, uniquingKeysWith: { first, _ in first })
            func recorded(_ node: DeviceNode) -> String? { node.internalParentID.flatMap { keyOfPart[$0] } }
            #expect(!partKeys.isEmpty, sourceLocation: sourceLocation)
            for part in dockParts {
                let parent = parentOf[key(part)]
                #expect(parent == key(dock) || parent.map(partKeys.contains) == true, sourceLocation: sourceLocation)
                #expect(recorded(part) == (parent == key(dock) ? nil : parent), sourceLocation: sourceLocation)
                #expect(part.internalParentID == nil || recorded(part) != nil, sourceLocation: sourceLocation)
                #expect(part.children.isEmpty, sourceLocation: sourceLocation)
            }
            for child in dock.children {
                let parent = parentOf[key(child)]
                #expect(recorded(child) == (parent == key(dock) ? nil : parent), sourceLocation: sourceLocation)
            }
            // Folding moves devices, not power.
            let original = unfolded.allDevices.first { key($0.device) == key(dock) }?.device
            #expect(original?.rolledUpMilliwatts == dock.rolledUpMilliwatts, sourceLocation: sourceLocation)
            #expect(original?.downstreamMilliwatts == dock.downstreamMilliwatts, sourceLocation: sourceLocation)
        }

        // Nothing a person plugged in is folded: a part that is not a hub is a
        // billboard (rule C), carries its holder's own IDs (rule B) or reports
        // a container ID (rule F). A function with none of these, like a
        // keyboard on a dock port wired to a captive hub, stays on the map.
        let records = Dictionary(raw.usbDevices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let switches = Dictionary(raw.thunderboltSwitches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for holder in docks {
            let own = holder.registryID.flatMap { switches[$0] }.map {
                ($0.node.properties.int("Device Vendor ID"), $0.node.properties.int("Device Model ID"))
            }
            for part in holder.internalParts ?? [] where part.deviceClass != DeviceClassifier.USBClass.hub {
                let record = part.registryID.flatMap { records[$0] }
                let billboard = part.deviceClass == DeviceClassifier.USBClass.billboard
                    || record.map { !$0.interfaces.isEmpty && $0.interfaces.allSatisfy {
                        $0.interfaceClass == DeviceClassifier.USBClass.billboard
                    } } == true
                let identity = own.map { $0.0 != nil && $0.0 == part.vendorID && $0.1 == part.productID } == true
                let container = record?.node.properties.string("kUSBContainerID")
                    .flatMap { PowerParser.normalizedUUID($0) }.map { $0.contains { $0 != "0" } } == true
                #expect(billboard || identity || container, "\(part.name) is folded without evidence",
                        sourceLocation: sourceLocation)
            }
        }

        // Unfolding gives back the tree: exactly when no device ID repeats,
        // by registry ID otherwise.
        let sameIDs = (folded.allDevices.map(\.device.id) + docks.flatMap { $0.internalParts ?? [] }.map(\.id))
            .sorted() == unfolded.allDevices.map(\.device.id).sorted()
        for (port, original) in zip(folded.ports, unfolded.ports) {
            let restored = TopologyBuilder.sortedTree(port.devices.map { $0.unfolded() })
            #expect(restored.map(shape).sorted() == original.devices.map(shape).sorted(),
                    sourceLocation: sourceLocation)
            if sameIDs { #expect(restored == original.devices, sourceLocation: sourceLocation) }
        }
        let restoredOther = TopologyBuilder.sortedTree(folded.otherDevices.map { $0.unfolded() })
        #expect(restoredOther.map(shape).sorted() == unfolded.otherDevices.map(shape).sorted(),
                sourceLocation: sourceLocation)
        if sameIDs { #expect(restoredOther == unfolded.otherDevices, sourceLocation: sourceLocation) }
    }

    @Test(arguments: DemoScenario.allCases)
    func demoScenarios(_ scenario: DemoScenario) {
        Self.check(scenario.raw(at: DemoTestSupport.date, tick: 0))
    }

    @Test func ankerCapture() throws {
        let raw = try AnkerPrimeDockTests.raw()
        Self.check(raw)
        // Five dock parts and the two Realtek hub chips.
        #expect(TopologyBuilder.build(raw).internalPartIDs.count == 7)
    }

    @Test func dellMonitorCapture() throws {
        let raw = try DellU4025QWTests.raw()
        Self.check(raw)
        #expect(TopologyBuilder.build(raw).internalPartIDs.count == 3)
    }

    @Test func macMiniCapture() throws {
        let url = try #require(Bundle.module.url(forResource: "MacMiniM4UgreenDock", withExtension: "json"))
        let raw = try Exporter.decodeRaw(Data(contentsOf: url))
        Self.check(raw)
        #expect(TopologyBuilder.build(raw).internalPartIDs.count == 1)
    }

    @Test func robustnessInputs() {
        Self.check(TopologyRobustnessTests.everything())
        var rng = TopologyTestRandom(seed: 0xD0C_4)
        for _ in 0..<200 { Self.check(TopologyRobustnessTests.randomRaw(&rng)) }
    }

    @Test func dockStationFoldsItsHubChip() {
        let snapshot = DemoTestSupport.snapshot(.dockStation)
        #expect(snapshot.internalPartIDs.count == 1)
    }
}
