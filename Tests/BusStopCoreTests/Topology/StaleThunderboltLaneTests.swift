import Foundation
import Testing
@testable import BusStopCore

/// A real capture: a MacBook Pro (M5 Max, macOS 27.0.1) with nothing plugged
/// in but the MagSafe charger (`Fixtures/StaleThunderboltLane.json`, saved
/// with `busstop --raw`, redacted).
///
/// After a Thunderbolt 5 device left Left Front (USB-C 2), the host lane
/// adapters for socket 2 kept its link: 40 Gb/s, width code 4 and a `Link
/// Bandwidth` of 400, with no switch below and an empty `Hop Table`. The
/// port node itself says the port is idle (`ConnectionActive` false, empty
/// `TransportsActive`), and the port node wins.
@Suite("Topology: stale Thunderbolt lane capture")
struct StaleThunderboltLaneTests {
    static func snapshot() throws -> HostSnapshot {
        let url = try #require(Bundle.module.url(forResource: "StaleThunderboltLane", withExtension: "json"))
        return TopologyBuilder.build(try Exporter.decodeRaw(Data(contentsOf: url)), options: BuildOptions())
    }

    @Test("A lane left over from an unplugged device does not mark the port connected")
    func staleLaneIsEmpty() throws {
        let port = try #require(try Self.snapshot().ports.first { $0.key == PortKey(type: 2, number: 2) })
        #expect(!port.isConnected)
        #expect(port.link == nil)
    }
}
