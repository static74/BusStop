import Foundation
import Testing
@testable import BusStopCore

@Suite("Topology: displays")
struct DisplayTopologyTests {
    typealias F = TopologyFixtures

    static let builtIn = RawDisplay(id: 1, name: "Color LCD", vendorID: 0x610, productID: 0xA050, serialNumber: 0,
                                    isBuiltin: true, isMain: true, pixelWidth: 3024, pixelHeight: 1964, refreshHz: 120)
    static let dell = RawDisplay(id: 2, name: "DELL U2723QE", vendorID: 0x10AC, productID: 0x42B4,
                                 serialNumber: 12345, isBuiltin: false, pixelWidth: 3840, pixelHeight: 2160,
                                 refreshHz: 60)
    static let lg = RawDisplay(id: 3, name: "LG HDR 4K", vendorID: 0x1E6D, productID: 0x7750, serialNumber: nil,
                               isBuiltin: false, pixelWidth: 3840, pixelHeight: 2160, refreshHz: 59.94)

    static func dpPort(id: UInt64, number: Int, product: String?) -> [RawNode] {
        var extra: [String: PlistValue] = ["LinkRate": 4, "LaneCount": 4]
        if let product { extra["ProductName"] = .string(product) }
        return [F.port(id: id, number: number, connected: true, active: ["CC", "DisplayPort"]),
                F.transport(id: id + 1, parent: id, kind: "DisplayPort", portNumber: number, extra: extra)]
    }

    @Test func displaysMatchTheirDisplayPortTransport() throws {
        let raw = F.raw(ports: Self.dpPort(id: 10, number: 1, product: "DELL U2723QE")
                            + Self.dpPort(id: 20, number: 2, product: "LG HDR 4K"),
                        displays: [Self.lg, Self.dell, Self.builtIn])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.displays.map(\.name) == ["Color LCD", "DELL U2723QE", "LG HDR 4K"])

        let builtIn = try #require(snapshot.displays.first)
        #expect(builtIn.isBuiltin)
        #expect(builtIn.portKey == nil)
        #expect(builtIn.id == "display:610:a050:cg1")
        #expect(builtIn.modeDescription == "3024 × 1964 @ 120 Hz")

        let dell = try #require(snapshot.displays.first { $0.name == "DELL U2723QE" })
        #expect(dell.id == "display:10ac:42b4:12345")
        #expect(dell.portKey == PortKey(type: 2, number: 1))
        #expect(dell.link?.detail == "HBR3 × 4")
        #expect(dell.link?.bitsPerSecond == 32_400_000_000)

        let port1 = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        let node = try #require(port1.devices.first)
        #expect(port1.devices.count == 1)
        #expect(node.id == dell.id)
        #expect(node.bus == .displayPort)
        #expect(node.kind == .display)
        #expect(node.vendorID == 0x10AC)
        #expect(node.serialNumber == "12345")
        #expect(node.link?.detail == "HBR3 × 4")
        #expect(port1.activeTransports.first?.productName == "DELL U2723QE")

        #expect(snapshot.port(PortKey(type: 2, number: 2))?.devices.map(\.name) == ["LG HDR 4K"])
        #expect(snapshot.displays.first { $0.name == "LG HDR 4K" }?.id == "display:1e6d:7750:cg3")
    }

    @Test func singleVideoPortAndSingleDisplay() throws {
        let raw = F.raw(ports: Self.dpPort(id: 10, number: 1, product: nil) + [F.port(id: 20, number: 2)],
                        displays: [Self.builtIn, Self.dell])
        let snapshot = TopologyBuilder.build(raw)
        let dell = try #require(snapshot.displays.first { !$0.isBuiltin })
        #expect(dell.portKey == PortKey(type: 2, number: 1))
        #expect(dell.link?.detail == "HBR3 × 4")
        #expect(snapshot.port(PortKey(type: 2, number: 1))?.devices.map(\.name) == ["DELL U2723QE"])
    }

    @Test func ambiguityFailsClosed() {
        // Two video ports, one display that names neither.
        let twoPorts = TopologyBuilder.build(F.raw(
            ports: Self.dpPort(id: 10, number: 1, product: nil) + Self.dpPort(id: 20, number: 2, product: nil),
            displays: [Self.dell]))
        #expect(twoPorts.displays.first?.portKey == nil)
        #expect(twoPorts.ports.allSatisfy { $0.devices.isEmpty })

        // One video port with one DisplayPort link, two displays: one of them
        // uses no port link (Sidecar, AirPlay, DisplayLink), so neither is placed.
        let twoDisplays = TopologyBuilder.build(F.raw(ports: Self.dpPort(id: 10, number: 1, product: nil),
                                                      displays: [Self.dell, Self.lg]))
        #expect(twoDisplays.displays.allSatisfy { $0.portKey == nil })
    }

    // MARK: Several displays on the only video port

    /// Port 1 with CIO up and the given tunnelled DisplayPort transports
    /// (`ProductName` or nil each).
    static func cioPort(products: [String?]) -> [RawNode] {
        var nodes = [F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"]),
                     F.transport(id: 11, parent: 10, kind: "CIO", portNumber: 1)]
        for (offset, product) in products.enumerated() {
            var extra: [String: PlistValue] = ["LinkRate": .int(Int64(4 - offset)), "LaneCount": 4]
            if let product { extra["ProductName"] = .string(product) }
            nodes.append(F.transport(id: 12 + UInt64(offset), parent: 11, kind: "DisplayPort", portNumber: 1,
                                     tunneled: true, extra: extra))
        }
        return nodes
    }

    @Test func twoUnnamedTunnelsOnTheOnlyVideoPort() throws {
        let snapshot = TopologyBuilder.build(F.raw(ports: Self.cioPort(products: [nil, nil]),
                                                   displays: [Self.builtIn, Self.dell, Self.lg]))
        let externals = snapshot.displays.filter { !$0.isBuiltin }
        #expect(externals.count == 2)
        #expect(externals.allSatisfy { $0.portKey == PortKey(type: 2, number: 1) })
        // Each display takes its own transport.
        #expect(Set(externals.compactMap { $0.link?.detail }).count == 2)
        let port = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        #expect(port.devices.map(\.name).sorted() == ["DELL U2723QE", "LG HDR 4K"])
        #expect(port.devices.allSatisfy { $0.isTunneled })
    }

    @Test func namedAndUnnamedTunnelsShareThePort() throws {
        let snapshot = TopologyBuilder.build(F.raw(ports: Self.cioPort(products: [nil, "LG HDR 4K"]),
                                                   displays: [Self.dell, Self.lg]))
        let lg = try #require(snapshot.displays.first { $0.name == "LG HDR 4K" })
        let dell = try #require(snapshot.displays.first { $0.name == "DELL U2723QE" })
        #expect(lg.portKey == PortKey(type: 2, number: 1))
        #expect(lg.link?.detail == "HBR2 × 4")
        // The Dell gets the transport the LG did not take.
        #expect(dell.portKey == PortKey(type: 2, number: 1))
        #expect(dell.link?.detail == "HBR3 × 4")
    }

    @Test func liveDisplayTunnelsCountWithoutTransports() throws {
        // A dock driving two displays, no DisplayPort transports published:
        // its two live display adapters still count.
        let host = F.tbSwitch(id: 1000, depth: 0, uid: 0x05AC_0000_0000_0001,
                              ports: [F.lane(id: 1001, portNumber: 1, socket: "1", speed: 0x2, width: 0x2)],
                              ancestry: F.hostAncestry(acio: 0))
        func dock(hops: [Bool]) -> RawThunderboltSwitch {
            F.tbSwitch(id: 1100, parent: 1000, depth: 1, uid: 0x003D_0000_0000_0002, vendor: "CalDigit, Inc.",
                       model: "TS5 Plus Dock", upstreamPort: 1,
                       ports: [F.lane(id: 1101, portNumber: 1, speed: 0x2, width: 0x2),
                               F.adapter(id: 1102, portNumber: 12, description: "USB Gen T Adapter", hops: true)]
                           + hops.enumerated().map { offset, live in
                               F.adapter(id: 1110 + UInt64(offset), portNumber: 10 + offset,
                                         description: "DP or HDMI Adapter", hops: live)
                           },
                       ancestry: [RawAncestor(id: 1001, className: "IOThunderboltPort", name: "IOThunderboltPort")]
                           + F.hostAncestry(acio: 0))
        }
        let ports = [F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"]),
                     F.transport(id: 11, parent: 10, kind: "CIO", portNumber: 1)]
        let both = TopologyBuilder.build(F.raw(ports: ports, thunderbolt: [host, dock(hops: [true, true])],
                                               displays: [Self.dell, Self.lg]))
        #expect(both.displays.allSatisfy { $0.portKey == PortKey(type: 2, number: 1) })
        #expect(both.displays.allSatisfy { $0.link == nil })
        let rows = both.port(PortKey(type: 2, number: 1))?.devices.filter { $0.bus == .displayPort } ?? []
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.isTunneled })
        #expect(both.port(PortKey(type: 2, number: 1))?.devices.first { $0.bus == .thunderbolt }?.kind == .dock)

        // One live tunnel, two displays: fail closed.
        let one = TopologyBuilder.build(F.raw(ports: ports, thunderbolt: [host, dock(hops: [true, false])],
                                              displays: [Self.dell, Self.lg]))
        #expect(one.displays.allSatisfy { $0.portKey == nil })
    }

    @Test func virtualDisplayStaysOffAThunderboltDisplaysPort() throws {
        // Only port 1, with the Studio Display, carries video.
        var raw = ThunderboltTopologyTests.raw()
        raw.portNodes.removeAll { [2, 21, 22].contains($0.id) }
        raw.thunderboltSwitches.removeAll { [2000, 2100].contains($0.id) }
        raw.displays = [Self.builtIn,
                        RawDisplay(id: 9, name: "Studio Display XDR", vendorID: 0x610, productID: 0xAE3A,
                                   serialNumber: 7, isBuiltin: false),
                        RawDisplay(id: 10, name: "Sidecar Display", isBuiltin: false, pixelWidth: 2732,
                                   pixelHeight: 2048)]
        let snapshot = TopologyBuilder.build(raw)
        let studio = try #require(snapshot.displays.first { $0.name == "Studio Display XDR" })
        #expect(studio.portKey == PortKey(type: 2, number: 1))
        #expect(studio.representingDeviceID == "tb:05ac000000001100")
        let sidecar = try #require(snapshot.displays.first { $0.name == "Sidecar Display" })
        #expect(sidecar.portKey == nil)
        #expect(sidecar.representingDeviceID == nil)
    }

    // MARK: Refresh rates

    @Test func hugeRefreshRateCannotTrap() throws {
        var raw = F.raw(ports: Self.dpPort(id: 10, number: 1, product: nil), displays: [Self.dell])
        raw.displays[0].refreshHz = 1e300
        let decoded = try Exporter.decodeRaw(Exporter.rawJSON(raw, redact: false))
        #expect(decoded.displays.first?.refreshHz == 1e300)
        let snapshot = TopologyBuilder.build(decoded)
        #expect(snapshot.displays.first?.refreshHz == nil)
        #expect(snapshot.displays.first?.modeDescription == "3840 × 2160")
        #expect(Exporter.textTree(snapshot).contains("DELL U2723QE · 3840 × 2160 · "))
        #expect(!Exporter.markdown(snapshot).contains(" Hz"))

        // A record built or decoded directly, without the parser.
        for rate in [1e300, 9.3e18, -1e30, .infinity, .nan, 10_000.4] {
            let info = DisplayInfo(id: "d", name: "D", isBuiltin: false, pixelWidth: 10, pixelHeight: 10, refreshHz: rate)
            #expect(info.modeDescription == "10 × 10", "\(rate)")
        }
        let normal = DisplayInfo(id: "d", name: "D", isBuiltin: false, pixelWidth: 10, pixelHeight: 10, refreshHz: 59.94)
        #expect(normal.modeDescription == "10 × 10 @ 60 Hz")
    }

    @Test func connectedHDMIPortCarriesVideo() throws {
        let hdmi = F.port(id: 30, type: 6, number: 1, description: "HDMI", connected: true, supported: [],
                          className: "AppleHDMIPortController")
        let snapshot = TopologyBuilder.build(F.raw(ports: [F.port(id: 10, number: 1), hdmi], displays: [Self.lg]))
        let port = try #require(snapshot.port(PortKey(type: 6, number: 1)))
        #expect(port.kind == .hdmi)
        #expect(port.devices.map(\.name) == ["LG HDR 4K"])
        #expect(snapshot.displays.first?.portKey == port.key)
    }

    @Test func hdmiHotPlugDetectCountsAsConnected() throws {
        let hdmi = RawNode(id: 30, className: "AppleHDMIPortController", name: "Port-HDMI", location: "1",
                           properties: ["PortTypeDescription": "HDMI", "PortNumber": 1, "HDMI_HPD": true])
        let snapshot = TopologyBuilder.build(F.raw(ports: [hdmi], displays: [Self.dell]))
        let port = try #require(snapshot.ports.first)
        #expect(port.key == PortKey(type: PortKey.hdmiType, number: 1))
        #expect(port.isConnected)
        #expect(port.devices.map(\.name) == ["DELL U2723QE"])
    }

    @Test func thunderboltDisplayIsNotDuplicated() throws {
        var raw = ThunderboltTopologyTests.raw()
        raw.displays = [Self.builtIn,
                        RawDisplay(id: 9, name: "Studio Display XDR", vendorID: 0x610, productID: 0xAE3A,
                                   serialNumber: 7, isBuiltin: false)]
        let snapshot = TopologyBuilder.build(raw)
        let display = try #require(snapshot.displays.first { !$0.isBuiltin })
        #expect(display.portKey == PortKey(type: 2, number: 1))
        #expect(display.link?.bitsPerSecond == 80_000_000_000)
        let port = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        #expect(port.devices.count == 1)
        #expect(port.devices.first?.bus == .thunderbolt)
        #expect(!snapshot.allDevices.contains { $0.device.bus == .displayPort })
    }

    @Test func tunnelledDisplayPortTransportCounts() throws {
        let raw = F.raw(ports: [
            F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"]),
            F.transport(id: 11, parent: 10, kind: "CIO", portNumber: 1),
            F.transport(id: 12, parent: 11, kind: "DisplayPort", portNumber: 1, tunneled: true,
                        extra: ["ProductName": "LG HDR 4K", "LinkRate": 3, "LaneCount": 2]),
            F.port(id: 20, number: 2, connected: true, active: ["CC", "CIO"]),
            F.transport(id: 21, parent: 20, kind: "CIO", portNumber: 2),
        ], displays: [Self.lg])
        let snapshot = TopologyBuilder.build(raw)
        let display = try #require(snapshot.displays.first)
        #expect(display.portKey == PortKey(type: 2, number: 1))
        let node = try #require(snapshot.port(PortKey(type: 2, number: 1))?.devices.first)
        #expect(node.isTunneled)
        #expect(node.link?.detail == "HBR2 × 2")
        #expect(snapshot.port(PortKey(type: 2, number: 1))?.activeTransports.map(\.kind) == [.cio])
    }

    @Test func nameAndModeFallbacks() {
        let info = DisplayParser.info(RawDisplay(id: 4, name: "  ", isBuiltin: false, pixelWidth: 0, pixelHeight: 1080,
                                                 refreshHz: .nan))
        #expect(info.name == "External Display")
        #expect(info.pixelWidth == nil)
        #expect(info.refreshHz == nil)
        #expect(info.modeDescription == nil)
        #expect(info.id == "display:0:0:cg4")
        #expect(DisplayParser.info(RawDisplay(id: 5, isBuiltin: true)).name == "Built-in Display")
    }
}
