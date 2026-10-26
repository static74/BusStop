import Foundation
import Testing
@testable import BusStopCore

/// A real capture: a Mac mini (M4, macOS 27.0.1) with a Dell P1425 monitor
/// on a USB-C cable in one rear port and a UGREEN DisplayLink dock (UG69PD10)
/// in another (`Fixtures/MacMiniM4UgreenDock.json`, saved with
/// `busstop --raw`, redacted). No Thunderbolt device and no charger.
///
/// The dock's Genesys hub runs at 10 Gb/s, and so does the port: its USB 3
/// transport says `DataRate` "10 Gbps" next to `SuperSpeedSignaling` "Gen 1".
@Suite("Topology: Mac mini M4 capture")
struct MacMiniM4CaptureTests {
    static func snapshot() throws -> HostSnapshot {
        let url = try #require(Bundle.module.url(forResource: "MacMiniM4UgreenDock", withExtension: "json"))
        return TopologyBuilder.build(try Exporter.decodeRaw(Data(contentsOf: url)))
    }

    static func port(_ number: Int, in snapshot: HostSnapshot) throws -> PhysicalPort {
        try #require(snapshot.port(PortKey(type: 2, number: number)))
    }

    @Test func portsAndLabels() throws {
        let snapshot = try Self.snapshot()
        #expect(snapshot.machine.name == "Mac mini (2024, M4)")
        // The capture predates `portLocations`, so ports sharing a catalogue name are numbered.
        #expect(snapshot.ports.map(\.label.title) == ["Front · USB-C 1", "Front · USB-C 2", "Rear · USB-C 1",
                                                     "Rear · USB-C 2", "Rear · USB-C 3", "Rear · HDMI"])
        #expect(snapshot.ports.filter(\.isConnected).map(\.key.number) == [1, 2])
        #expect(snapshot.deviceCount == 9)
    }

    @Test func monitorOnAUSBCCable() throws {
        let snapshot = try Self.snapshot()
        let port = try Self.port(1, in: snapshot)
        #expect(port.link?.label == "DisplayPort @ 10.8 Gb/s")
        #expect(port.devices.map(\.name) == ["DELL P1425"])
        // The monitor draws from the port, measured by the SMC.
        #expect(port.power?.direction == .output)
        #expect(port.power?.isMeasured == true)
        #expect(port.power?.milliwatts == 4_427)
        #expect(snapshot.displays.map(\.portKey) == [port.key])
    }

    /// The port runs at the rate the hub negotiated, not at the Gen 1 rate
    /// that `SuperSpeedSignaling` alone suggests.
    @Test func usbPortRunsAtTheHubsRate() throws {
        let port = try Self.port(2, in: Self.snapshot())
        let hub = try #require(port.devices.first)
        #expect(hub.name == "USB3.2 Hub")
        #expect(hub.link?.bitsPerSecond == 10_000_000_000)
        #expect(port.link?.bitsPerSecond == 10_000_000_000)
        #expect(port.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(port.allocatedMilliwatts == 5_760)
    }

    @Test func textTree() throws {
        let text = Exporter.textTree(try Self.snapshot())
        let expected = """
        ├─ Rear · USB-C 1   DisplayPort @ 10.8 Gb/s   ↑ 4.4 W
        │  └─ DELL P1425 · 10.8 Gb/s
        ├─ Rear · USB-C 2   USB 3.2 Gen 2 @ 10 Gb/s   ↑ 5.8 W
        │  └─ USB3.2 Hub · 10 Gb/s · 5.8 W
        │     ├─ UG69PD10 Docking · 5 Gb/s
        │     ├─ UG69PD10 Docking · 5 Gb/s
        │     └─ USB3.0 Hub · 5 Gb/s · 5.8 W
        │        ├─ Generic Billboard Device · 12 Mb/s
        │        ├─ USB 10_100_1G_2_5G LAN · 5 Gb/s · 1.3 W
        │        ├─ USB Storage · 5 Gb/s · 4.5 W
        │        └─ USB3.0 Hub · 5 Gb/s
        ├─ Rear · USB-C 3   (empty)
        """
        #expect(text.contains(expected), "\(text)")
    }
}
