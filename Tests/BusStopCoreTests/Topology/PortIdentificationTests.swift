import Foundation
import Testing
@testable import BusStopCore

@Suite("Identify this port")
struct PortIdentificationTests {
    typealias F = TopologyFixtures

    static func snapshot(connected: Set<Int> = [], model: String = F.genericModel,
                         names: [String: String] = [:]) -> HostSnapshot {
        let ports = [1, 2, 3].map { number in
            F.port(id: 0x100 + UInt64(number), number: number, connected: connected.contains(number))
        }
        return TopologyBuilder.build(F.raw(model: model, ports: ports), options: BuildOptions(userPortNames: names))
    }

    @Test func pluggingInFindsThePort() {
        let key = PortIdentification.changedPort(from: Self.snapshot(), to: Self.snapshot(connected: [2]))
        #expect(key == PortKey(type: 2, number: 2))
    }

    @Test func unpluggingFindsThePortToo() {
        let key = PortIdentification.changedPort(from: Self.snapshot(connected: [1, 3]),
                                                 to: Self.snapshot(connected: [1]))
        #expect(key == PortKey(type: 2, number: 3))
    }

    @Test func noChangeOrSeveralChangesFindNothing() {
        #expect(PortIdentification.changedPort(from: Self.snapshot(), to: Self.snapshot()) == nil)
        #expect(PortIdentification.changedPort(from: Self.snapshot(), to: Self.snapshot(connected: [1, 2])) == nil)
    }

    /// A device behind a hub on a port that stays connected still counts.
    @Test func aDeviceChangeOnAConnectedPortCounts() throws {
        let before = Self.snapshot(connected: [1])
        var after = before
        let index = try #require(after.ports.firstIndex { $0.key.number == 1 })
        after.ports[index].devices = [DeviceNode(id: "usb:1", bus: .usb, kind: .keyboard, name: "Keyboard")]
        #expect(PortIdentification.changedPort(from: before, to: after) == PortKey(type: 2, number: 1))
    }

    /// A port only one snapshot has is not a change the user made.
    @Test func portsMissingFromEitherSnapshotAreIgnored() {
        var after = Self.snapshot(connected: [2])
        after.ports.removeAll { $0.key.number == 1 }
        #expect(PortIdentification.changedPort(from: Self.snapshot(), to: after) == PortKey(type: 2, number: 2))
    }

    @Test func catalogEntryUsesTheCurrentNames() throws {
        let snapshot = Self.snapshot(model: "Mac16,10", names: ["2/2": "Rear (center)"])
        let json = try PortIdentification.catalogEntry(for: snapshot)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let model = try #require(object["Mac16,10"] as? [String: Any])
        #expect(model["marketing_name"] as? String == "Mac mini (2024, M4)")
        #expect(model["chassis"] as? String == "Mac mini (2024 redesign)")
        let ports = try #require(model["ports"] as? [[String: Any]])
        let byNumber = Dictionary(uniqueKeysWithValues: ports.map { ($0["port_number"] as? Int ?? 0, $0) })
        #expect(byNumber[2]?["location"] as? String == "Rear (center)")
        #expect(byNumber[2]?["connector"] as? String == "usb-c")
        #expect(ports.count == 3)
    }

    /// Ports with no name of any kind are left out.
    @Test func catalogEntrySkipsUnnamedPorts() throws {
        let json = try PortIdentification.catalogEntry(for: Self.snapshot(names: ["2/1": "Left"]))
        #expect(json.contains("\"location\" : \"Left\""))
        #expect(!json.contains("\"port_number\" : 2"))
    }
}
