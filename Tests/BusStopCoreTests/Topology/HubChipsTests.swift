import Foundation
import Testing
@testable import BusStopCore

/// A USB hub built from several hub chips folds into one card (SPEC §5.4
/// "Hub chips"). The real captures cover a hub on a display
/// (`DellU4025QWTests`) and on a dock (`AnkerPrimeDockTests`); these cover
/// the rule itself, on hand-made captures.
@Suite("Topology: hub chips")
struct HubChipsTests {
    typealias F = TopologyFixtures

    static func top(_ raw: RawSnapshot) throws -> DeviceNode {
        try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 1))?.devices.first)
    }

    static func partIDs(_ node: DeviceNode) -> [String] {
        (node.internalParts ?? []).compactMap(\.registryID).sorted().map { "\($0)" }
    }

    @Test func captiveHubFolds() throws {
        let raw = F.hubChain(chips: 2)
        let hub = try Self.top(raw)
        #expect(Self.partIDs(hub) == ["11"])
        #expect(hub.children.map(\.name) == ["Keyboard"])
        #expect(hub.children.first?.internalParentID == hub.internalParts?.first?.id)
        DockPartsInvariantTests.check(raw)
    }

    @Test func threeChipsCollapseToTheTop() throws {
        let raw = F.hubChain(chips: 3)
        let hub = try Self.top(raw)
        #expect(Self.partIDs(hub) == ["11", "12"])
        let parents = Dictionary(uniqueKeysWithValues: (hub.internalParts ?? []).map {
            ($0.registryID ?? 0, $0.internalParentID)
        })
        #expect(parents[11] == .some(nil))
        #expect(parents[12] == (hub.internalParts ?? []).first { $0.registryID == 11 }?.id)
        #expect(hub.descendantCount == 1)
        DockPartsInvariantTests.check(raw)
    }

    @Test func hubOnAStandardPortStays() throws {
        let hub = try Self.top(F.hubChain(chips: 2, portType: 0))
        #expect(hub.internalParts == nil)
        #expect(hub.children.map(\.name) == ["Hub"])
    }

    /// Only hubs are chips: a function on a captive port is something a
    /// person uses, and stays on the map.
    @Test func captiveFunctionStays() throws {
        var raw = F.hubChain(chips: 1)
        let index = try #require(raw.usbDevices.firstIndex { $0.id == 99 })
        raw.usbDevices[index].node.properties["USBPortType"] = 1
        let hub = try Self.top(raw)
        #expect(hub.internalParts == nil)
        #expect(hub.children.map(\.name) == ["Keyboard"])
    }

    /// A merged USB 3 hub is a chip only when both halves are on captive ports.
    @Test(arguments: [(1, 1, true), (1, 0, false), (0, 1, false)])
    func mergedHubNeedsBothHalvesCaptive(superSpeed: Int, usb2: Int, folds: Bool) throws {
        let raw = F.raw(ports: [F.port(id: 1, number: 1, connected: true, active: ["CC", "USB2", "USB3"])], usb: [
            F.usb(id: 10, name: "USB3.0 Hub", vendor: 0x2109, product: 0x0817, location: 0x0110_0000,
                  speed: 5_000_000_000, deviceClass: 9, bcdUSB: 0x0320, path: "x/Port-USB-C@1"),
            F.usb(id: 11, name: "USB2.0 Hub", vendor: 0x2109, product: 0x2817, location: 0x0120_0000,
                  deviceClass: 9, bcdUSB: 0x0210, path: "x/Port-USB-C@1"),
            F.usb(id: 20, parent: 10, name: "USB3.0 Hub", vendor: 0x2109, product: 0x0817, location: 0x0111_0000,
                  speed: 5_000_000_000, deviceClass: 9, bcdUSB: 0x0320,
                  extra: ["USBPortType": .int(Int64(superSpeed))]),
            F.usb(id: 21, parent: 11, name: "USB2.0 Hub", vendor: 0x2109, product: 0x2817, location: 0x0121_0000,
                  deviceClass: 9, bcdUSB: 0x0210, extra: ["USBPortType": .int(Int64(usb2))]),
        ])
        let hub = try Self.top(raw)
        #expect(Self.partIDs(hub) == (folds ? ["20"] : []))
        #expect(hub.children.isEmpty == folds)
        DockPartsInvariantTests.check(raw)
    }

    @Test func foldingOffKeepsEveryChip() throws {
        let snapshot = TopologyBuilder.build(F.hubChain(chips: 3), options: BuildOptions(), foldsDockParts: false)
        #expect(snapshot.internalPartIDs.isEmpty)
        #expect(snapshot.deviceCount == 4)
    }
}
