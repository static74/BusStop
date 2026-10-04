import Foundation
import Testing
@testable import BusStopCore

/// Regression tests for the display attribution the dock station scenario
/// exposed: a Thunderbolt dock with idle display adapters made the only
/// display on the HDMI port ambiguous.
@Suite("Demo scenarios: display regressions")
struct DemoDisplayRegressionTests {
    typealias F = TopologyFixtures

    static let lg = RawDisplay(id: 2, name: "LG UltraFine", vendorID: 0x1E6D, productID: 0x5B71, serialNumber: 1234,
                               isBuiltin: false, pixelWidth: 3840, pixelHeight: 2160, refreshHz: 60)

    /// Port 1: a Thunderbolt dock; HDMI port: a display behind hot-plug
    /// detect only. `displayHops` sets the dock's display adapter `Hop
    /// Table`: empty (idle), non-empty (a display tunnel) or missing.
    static func dockAndHDMI(displayHops: Bool?, hdmiConnected: Bool = true) -> RawSnapshot {
        let host = F.tbSwitch(id: 1000, depth: 0, uid: 0x05AC_0000_0000_0001,
                              ports: [F.lane(id: 1001, portNumber: 1, socket: "1", speed: 0x2, width: 0x2)],
                              ancestry: F.hostAncestry(acio: 0))
        var displayAdapter = F.adapter(id: 1103, portNumber: 10, description: "DP or HDMI Adapter",
                                       hops: displayHops ?? false)
        if displayHops == nil { displayAdapter.properties["Hop Table"] = nil }
        let dock = F.tbSwitch(
            id: 1100, parent: 1000, depth: 1, uid: 0x003D_0000_0000_0002, vendor: "CalDigit, Inc.", model: "TS5 Plus",
            upstreamPort: 1,
            ports: [F.lane(id: 1101, portNumber: 1, speed: 0x2, width: 0x2),
                    F.adapter(id: 1102, portNumber: 12, description: "USB Gen T Adapter", hops: true), displayAdapter],
            ancestry: [RawAncestor(id: 1001, className: "IOThunderboltPort", name: "IOThunderboltPort")]
                + F.hostAncestry(acio: 0))
        let hdmi = RawNode(id: 30, className: "AppleHDMIPortController", name: "Port-HDMI", location: "1",
                           properties: ["PortTypeDescription": "HDMI", "PortType": 6, "PortNumber": 1,
                                        "HDMI_HPD": .bool(hdmiConnected)])
        return F.raw(ports: [F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"]),
                             F.transport(id: 11, parent: 10, kind: "CIO", portNumber: 1),
                             F.transport(id: 12, parent: 11, kind: "USB3", portNumber: 1, tunneled: true,
                                         path: "Port-USB-C@1/CIO/USB3@0"),
                             hdmi],
                     thunderbolt: [host, dock], displays: [lg])
    }

    @Test func idleDockDoesNotHideTheHDMIDisplay() throws {
        let snapshot = TopologyBuilder.build(Self.dockAndHDMI(displayHops: false))
        let hdmi = try #require(snapshot.port(PortKey(type: 6, number: 1)))
        #expect(hdmi.devices.map(\.name) == ["LG UltraFine"])
        #expect(snapshot.displays.first?.portKey == hdmi.key)
        #expect(snapshot.port(PortKey(type: 2, number: 1))?.devices.map(\.kind) == [.dock])
    }

    @Test func dockThatMayCarryADisplayStaysAmbiguous() {
        // A live display tunnel on the dock: the display could be on either port.
        let live = TopologyBuilder.build(Self.dockAndHDMI(displayHops: true))
        #expect(live.displays.first?.portKey == nil)
        // No `Hop Table` at all: unknown, so still ambiguous.
        let unknown = TopologyBuilder.build(Self.dockAndHDMI(displayHops: nil))
        #expect(unknown.displays.first?.portKey == nil)
        #expect(unknown.ports.allSatisfy { $0.devices.allSatisfy { $0.kind != .display } })
    }

    @Test func singleVideoPortRuleIsUnchanged() {
        // With the HDMI port empty the dock is the only video port, as before
        // (a USB display adapter in the dock, for example).
        let snapshot = TopologyBuilder.build(Self.dockAndHDMI(displayHops: false, hdmiConnected: false))
        #expect(snapshot.displays.first?.portKey == PortKey(type: 2, number: 1))
    }
}
