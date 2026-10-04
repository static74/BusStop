import Foundation
import Testing
@testable import BusStopCore

/// A hand-made capture can describe parent chains far longer than any real
/// bus. Building, rendering and diffing such a capture must finish without
/// exhausting the stack.
@Suite("Topology: chain depth limits")
struct TopologyDepthTests {
    typealias F = TopologyFixtures

    static let chainLength = 10_000

    static func maxDepth(_ snapshot: HostSnapshot) -> Int {
        snapshot.allDevices.map(\.depth).max() ?? -1
    }

    @Test func longUSBChainIsCutIntoShallowTrees() {
        let devices = (0..<Self.chainLength).map { i in
            F.usb(id: UInt64(1_000 + i), parent: i == 0 ? nil : UInt64(999 + i), name: "Hub \(i)",
                  deviceClass: 9, drd: 1)
        }
        let raw = F.raw(ports: [F.port(id: 10, number: 1, connected: true, active: ["CC", "USB2"])], usb: devices)
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.deviceCount == Self.chainLength)
        #expect(Self.maxDepth(snapshot) == USBTreeBuilder.maxTreeDepth)
        #expect(!Exporter.textTree(snapshot).isEmpty)
        #expect(!Exporter.markdown(snapshot).isEmpty)
        #expect(SnapshotDiffer.events(from: snapshot, to: snapshot, at: F.date).isEmpty)
    }

    @Test func longThunderboltChainStopsAtTheDepthLimit() {
        let host = F.tbSwitch(id: 1, depth: 0, uid: 0x05AC_0000_0000_0001,
                              ports: [F.lane(id: 2, portNumber: 1, socket: "1", speed: 0x2, width: 0x2)],
                              ancestry: F.hostAncestry(acio: 0))
        let chain = (0..<Self.chainLength).map { i in
            F.tbSwitch(id: UInt64(100 + i), parent: i == 0 ? 1 : UInt64(99 + i), depth: i + 1,
                       uid: 0x0100_0000_0000_0000 + Int64(i), vendor: "Vendor", model: "Device \(i)",
                       ancestry: i == 0 ? [RawAncestor(id: 2, className: "IOThunderboltPort", name: "IOThunderboltPort")]
                           + F.hostAncestry(acio: 0) : [])
        }
        let raw = F.raw(ports: [F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"]),
                                F.transport(id: 11, parent: 10, kind: "CIO", portNumber: 1)],
                        thunderbolt: [host] + chain)
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.deviceCount == ThunderboltParser.maxChainDepth)
        #expect(Self.maxDepth(snapshot) == ThunderboltParser.maxChainDepth - 1)
        #expect(!Exporter.textTree(snapshot).isEmpty)
        #expect(snapshot.diagnostics.contains { $0.kind == .deepChain })
    }
}
