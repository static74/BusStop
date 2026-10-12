import Foundation
import Testing
@testable import BusStopCore

/// Regression test for the power figures the dock station scenario exposed.
@Suite("Demo scenarios: power regressions")
struct DemoPowerRegressionTests {
    typealias F = TopologyFixtures

    @Test func tunnelledDevicesDoNotCountAsMacPower() throws {
        let raw = F.raw(ports: [F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"]),
                                F.port(id: 20, number: 2, connected: true, active: ["CC", "USB3"])],
                        usb: [
                            // On a dock's own controller, behind the Thunderbolt tunnel.
                            F.usb(id: 50, name: "Dock SSD", location: 0x0520_0000, speed: 20_000_000_000,
                                  allocation: 896, ancestry: F.tunnelAncestry(pcie: 0)),
                            // On a USB4 tunnel through the port's own controller.
                            F.usb(id: 51, name: "Tunnelled Drive", location: 0x0020_0000, speed: 10_000_000_000,
                                  allocation: 896, path: "x/Port-USB-C@1", extra: ["UsbTunnel": true]),
                            // Plugged straight into port 2.
                            F.usb(id: 52, name: "Flash Drive", location: 0x0120_0000, speed: 5_000_000_000,
                                  allocation: 896, path: "x/Port-USB-C@2"),
                        ],
                        thunderbolt: [F.tbSwitch(id: 1000, depth: 0, uid: 1,
                                                 ports: [F.lane(id: 1001, portNumber: 1, socket: "1", speed: 0x2,
                                                                width: 0x2)],
                                                 ancestry: F.hostAncestry(acio: 0))])
        let snapshot = TopologyBuilder.build(raw)
        let dockPort = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        #expect(dockPort.devices.map(\.name) == ["Dock SSD", "Tunnelled Drive"])
        #expect(dockPort.devices.allSatisfy { $0.isTunneled })
        // The allocations stay on the devices, but the Mac does not supply them.
        #expect(dockPort.allocatedMilliwatts == 2 * 4_480)
        #expect(dockPort.power == nil)
        let direct = try #require(snapshot.port(PortKey(type: 2, number: 2)))
        #expect(direct.power?.milliwatts == 4_480)
        #expect(direct.power?.source == .usbAllocation)
        #expect(snapshot.power.usbAllocatedMilliwatts == 4_480)
        #expect(snapshot.power.portOutputMilliwatts == 4_480)
        #expect(snapshot.power.headlineMilliwatts == 4_480)
    }
}
