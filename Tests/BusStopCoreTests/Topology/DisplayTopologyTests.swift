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

        // One video port, two displays (daisy-chained over MST, say).
        let twoDisplays = TopologyBuilder.build(F.raw(ports: Self.dpPort(id: 10, number: 1, product: nil),
                                                      displays: [Self.dell, Self.lg]))
        #expect(twoDisplays.displays.allSatisfy { $0.portKey == nil })
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
