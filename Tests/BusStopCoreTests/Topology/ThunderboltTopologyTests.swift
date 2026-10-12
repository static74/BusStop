import Foundation
import Testing
@testable import BusStopCore

/// A Thunderbolt 5 desk: port 1 → Studio Display XDR at 80 Gb/s → SSD at
/// 40 Gb/s; port 2 → a USB4 dock at 40 Gb/s with tunnelled USB devices;
/// port 3 idle with the old controllers' idle defaults on its lane.
@Suite("Topology: Thunderbolt chains")
struct ThunderboltTopologyTests {
    typealias F = TopologyFixtures

    static let displayUID: Int64 = 0x05AC_0000_0000_1100
    static let ssdUID: Int64 = 0x01C3_0000_0000_1200
    static let dockUID: Int64 = 0x2B89_0000_0000_2100

    static var ports: [RawNode] {
        [
            F.port(id: 1, number: 1, connected: true, active: ["CC", "CIO"]),
            F.transport(id: 11, parent: 1, kind: "CIO", portNumber: 1),
            F.port(id: 2, number: 2, connected: true, active: ["CC", "CIO"]),
            F.transport(id: 21, parent: 2, kind: "CIO", portNumber: 2),
            F.transport(id: 22, parent: 21, kind: "USB3", portNumber: 2, tunneled: true,
                        path: "Port-USB-C@2/CIO/USB3@0"),
            F.port(id: 3, number: 3, supported: ["CC", "USB2", "USB3"]),
        ]
    }

    static var switches: [RawThunderboltSwitch] {
        let hostA = F.tbSwitch(id: 1000, depth: 0, uid: 0x05AC_11E6_A043_0001, vendor: "Apple Inc.", model: "MacBook Pro",
                               ports: [F.lane(id: 1001, portNumber: 1, socket: "1", speed: 0x2, width: 0x2),
                                       // Second lane of the bonded pair: no peer, so never the live link.
                                       F.lane(id: 1002, portNumber: 2, socket: "1", speed: 0x2, width: 0x2,
                                              extra: ["Link Bandwidth": 0])],
                               ancestry: F.hostAncestry(acio: 0))
        let hostB = F.tbSwitch(id: 2000, depth: 0, uid: 0x05AC_11E6_A043_0002,
                               ports: [F.lane(id: 2001, portNumber: 1, socket: "2", speed: 0x4, width: 0x2)],
                               ancestry: F.hostAncestry(acio: 1))
        let hostC = F.tbSwitch(id: 3000, depth: 0, uid: 0x05AC_11E6_A043_0003,
                               ports: [F.lane(id: 3001, portNumber: 1, socket: "3", speed: 0x8, width: 0x1,
                                              extra: ["Link Bandwidth": 100, "Hop Table": .array([])])],
                               ancestry: F.hostAncestry(acio: 2))
        let display = F.tbSwitch(
            id: 1100, parent: 1000, depth: 1, uid: displayUID, vendor: "Apple Inc.", model: "Studio Display XDR",
            upstreamPort: 1,
            ports: [F.lane(id: 1101, portNumber: 1, speed: 0x2, width: 0x2),
                    F.lane(id: 1102, portNumber: 3, speed: 0x4, width: 0x2),
                    F.adapter(id: 1103, portNumber: 10, description: "DP or HDMI Adapter", hops: true),
                    F.adapter(id: 1104, portNumber: 12, description: "USB Adapter", hops: true)],
            ancestry: [RawAncestor(id: 1001, className: "IOThunderboltPort", name: "IOThunderboltPort")]
                + F.hostAncestry(acio: 0))
        let ssd = F.tbSwitch(
            id: 1200, parent: 1100, depth: 2, uid: ssdUID, vendor: "OWC", model: "Envoy Ultra", upstreamPort: 1,
            ports: [F.lane(id: 1201, portNumber: 1, speed: 0x4, width: 0x2),
                    F.adapter(id: 1202, portNumber: 8, description: "PCIe Adapter", hops: true)],
            ancestry: [RawAncestor(id: 1102, className: "IOThunderboltPort", name: "IOThunderboltPort"),
                       RawAncestor(id: 1100, className: "IOThunderboltSwitchType7", name: "IOThunderboltSwitchType7"),
                       RawAncestor(id: 1001, className: "IOThunderboltPort", name: "IOThunderboltPort")]
                + F.hostAncestry(acio: 0))
        let dock = F.tbSwitch(
            id: 2100, parent: 2000, depth: 1, uid: dockUID, vendor: "Ugreen",
            model: "Ugreen Ugreen USB4 Docking Station", upstreamPort: 1,
            ports: [F.lane(id: 2101, portNumber: 1, speed: 0x4, width: 0x2),
                    F.adapter(id: 2102, portNumber: 9, description: "USB Adapter", hops: true),
                    F.adapter(id: 2103, portNumber: 10, description: "DP or HDMI Adapter", hops: false)],
            ancestry: [RawAncestor(id: 2001, className: "IOThunderboltPort", name: "IOThunderboltPort")]
                + F.hostAncestry(acio: 1))
        return [ssd, dock, display, hostC, hostB, hostA]
    }

    static var usb: [RawUSBDevice] {
        [
            // The display's own USB endpoint (exact name): nested under it.
            F.usb(id: 500, name: "Studio Display XDR", vendor: 0x05AC, product: 0x1114, location: 0x0310_0000,
                  speed: 5_000_000_000, deviceClass: 9, ancestry: F.tunnelAncestry(pcie: 0)),
            F.usb(id: 501, parent: 500, name: "Studio Display XDR Camera", vendor: 0x05AC, product: 0x1115,
                  location: 0x0311_0000, ancestry: F.tunnelAncestry(pcie: 0),
                  interfaces: [RawUSBInterface(interfaceClass: 14)]),
            // The dock's hub (name contains the model): nested under the dock.
            F.usb(id: 600, name: "Ugreen USB4 Docking Station Hub", vendor: 0x2B89, location: 0x0410_0000,
                  speed: 10_000_000_000, deviceClass: 9, ancestry: F.tunnelAncestry(pcie: 1, base: 0xC_0000)),
            F.usb(id: 601, parent: 600, name: "Keyboard", vendor: 0x046D, location: 0x0411_0000,
                  ancestry: F.tunnelAncestry(pcie: 1, base: 0xC_0000),
                  interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1, interfaceProtocol: 1)]),
            // No name match: stays at port level.
            F.usb(id: 602, name: "USB Ethernet", vendor: 0x0BDA, location: 0x0420_0000, speed: 5_000_000_000,
                  ancestry: F.tunnelAncestry(pcie: 1, base: 0xC_0000),
                  interfaces: [RawUSBInterface(interfaceClass: 2, interfaceSubClass: 13)]),
        ]
    }

    static func raw() -> RawSnapshot {
        F.raw(ports: ports, usb: usb, thunderbolt: switches)
    }

    let snapshot = TopologyBuilder.build(Self.raw())

    @Test func port1LinkIsTheHostLane() throws {
        let port = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        #expect(port.activeTransports.map(\.kind) == [.cio])
        let cio = try #require(port.activeTransports.first?.link)
        #expect(cio.family == .thunderbolt)
        #expect(cio.label == "USB4 v2 / TB5 @ 80 Gb/s")
        #expect(cio.detail == "2 × 40 Gb/s")
        #expect(port.link == cio)
        #expect(port.supportsThunderbolt)
    }

    @Test func displayChainWithSSDBehindIt() throws {
        let port = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        #expect(port.devices.count == 1)
        let display = try #require(port.devices.first)
        #expect(display.id == "tb:05ac000000001100")
        #expect(display.bus == .thunderbolt)
        #expect(display.kind == .display)
        #expect(display.name == "Studio Display XDR")
        #expect(display.vendorName == "Apple Inc.")
        #expect(display.chainDepth == 1)
        #expect(display.link?.bitsPerSecond == 80_000_000_000)
        #expect(!display.isTunneled)
        #expect(display.children.map(\.name) == ["Envoy Ultra", "Studio Display XDR"])

        let ssd = try #require(display.children.first)
        #expect(ssd.id == "tb:01c3000000001200")
        #expect(ssd.kind == .thunderboltDevice)
        #expect(ssd.chainDepth == 2)
        #expect(ssd.link?.label == "Thunderbolt / USB4 @ 40 Gb/s")

        let endpoint = try #require(display.children.last)
        #expect(endpoint.bus == .usb)
        #expect(endpoint.isTunneled)
        #expect(endpoint.children.map(\.name) == ["Studio Display XDR Camera"])
        #expect(endpoint.children.first?.isTunneled == true)
        #expect(port.deviceCount == 4)
    }

    @Test func dockWithTunnelledDevices() throws {
        let port = try #require(snapshot.port(PortKey(type: 2, number: 2)))
        #expect(port.activeTransports.map(\.kind) == [.cio])
        #expect(port.link?.label == "Thunderbolt / USB4 @ 40 Gb/s")
        #expect(port.devices.map(\.name) == ["Ugreen USB4 Docking Station", "USB Ethernet"])

        let dock = try #require(port.devices.first)
        #expect(dock.kind == .dock)
        #expect(dock.vendorName == "Ugreen")
        #expect(dock.children.map(\.name) == ["Ugreen USB4 Docking Station Hub"])
        #expect(dock.children.first?.children.map(\.name) == ["Keyboard"])

        let ethernet = try #require(port.devices.last)
        #expect(ethernet.isTunneled)
        #expect(ethernet.kind == .network)
    }

    @Test func idleLaneDefaultsAreNotALink() throws {
        let port = try #require(snapshot.port(PortKey(type: 2, number: 3)))
        #expect(port.link == nil)
        #expect(port.activeTransports.isEmpty)
        #expect(!port.isConnected)
        #expect(port.devices.isEmpty)
        // supportedTransports mirrors TransportsSupported; the socket only
        // feeds the label hint.
        #expect(port.supportedTransports == [.usb3, .usb2])
    }

    @Test func nothingIsLeftOver() {
        #expect(snapshot.otherDevices.isEmpty)
        #expect(snapshot.deviceCount == 8)
    }

    @Test func parserLinksAndSockets() {
        let topology = ThunderboltParser.parse(Self.switches, options: BuildOptions())
        #expect(topology.allSockets == [1, 2, 3])
        #expect(topology.socketsByACIO == [0: [1], 1: [2], 2: [3]])
        #expect(topology.liveLinks[1]?.bitsPerSecond == 80_000_000_000)
        #expect(topology.liveLinks[2]?.bitsPerSecond == 40_000_000_000)
        #expect(topology.liveLinks[3] == nil)
        #expect(topology.decodedLinks[3]?.bitsPerSecond == 10_000_000_000)
        #expect(topology.socket(forPCIeIndex: 1) == 2)
        #expect(topology.socket(forPCIeIndex: 7) == nil)
    }

    @Test func idleLaneCountsWhenThePortSaysCIOIsActive() throws {
        var ports = Self.ports
        ports.append(F.transport(id: 31, parent: 3, kind: "CIO", portNumber: 3))
        if let i = ports.firstIndex(where: { $0.id == 3 }) {
            ports[i] = F.port(id: 3, number: 3, connected: true, active: ["CC", "CIO"])
        }
        let snapshot = TopologyBuilder.build(F.raw(ports: ports, thunderbolt: Self.switches))
        #expect(snapshot.port(PortKey(type: 2, number: 3))?.link?.label == "Thunderbolt @ 10 Gb/s")
    }

    @Test func asymmetricHostLane() throws {
        let host = F.tbSwitch(id: 1, depth: 0, ports: [F.lane(id: 2, portNumber: 1, socket: "1", speed: 0x2,
                                                             width: 0x4, extra: ["Link Bandwidth": 1200])],
                              ancestry: F.hostAncestry(acio: 0))
        let snapshot = TopologyBuilder.build(F.raw(ports: [F.port(id: 10, number: 1, connected: true,
                                                                  active: ["CC", "CIO"])],
                                                   thunderbolt: [host]))
        let link = try #require(snapshot.ports.first?.link)
        #expect(link.isAsymmetric)
        #expect(link.lanes == 3)
        #expect(link.bitsPerSecond == 120_000_000_000)
        #expect(link.generation == "USB4 v2 / TB5")
    }

    @Test func singleCIOPortIsTheTunnelFallback() throws {
        // The device's ancestry stops at the tunnel controller (no apciecN).
        let ancestry = [RawAncestor(id: 5, className: "AppleUSBXHCITR", name: "AppleUSBXHCITR")]
        let raw = F.raw(ports: [F.port(id: 1, number: 1, connected: true, active: ["CC", "CIO"]),
                                F.port(id: 2, number: 2, connected: true, active: ["CC", "USB2"])],
                        usb: [F.usb(id: 9, name: "Tunnelled Drive", location: 0x0510_0000, drd: 2, ancestry: ancestry)])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.port(PortKey(type: 2, number: 1))?.devices.map(\.name) == ["Tunnelled Drive"])
        #expect(snapshot.port(PortKey(type: 2, number: 1))?.devices.first?.isTunneled == true)
    }

    @Test func dockControllersCountAsTunnels() {
        let fl1100 = [RawAncestor(id: 1, className: "AppleUSBXHCIFL1100", name: "XHC0"),
                      RawAncestor(id: 2, className: "IOPCI2PCIBridge", name: "pci-bridge")]
        let generic = [RawAncestor(id: 1, className: "AppleUSBXHCIVendorX", name: "XHC0"),
                       RawAncestor(id: 2, className: "IOPCI2PCIBridge", name: "pci-bridge"),
                       RawAncestor(id: 3, className: "AppleT6050PCIeC", name: "apciec3")]
        let native = F.nativeAncestry(drd: 0)
        let embedded = [RawAncestor(id: 1, className: "AppleEmbeddedUSBXHCIASMedia3142", name: "XHC1"),
                        RawAncestor(id: 2, className: "AppleT6050PCIeC", name: "apciec0")]
        #expect(USBTreeBuilder.hasTunnelAncestry(fl1100))
        #expect(USBTreeBuilder.hasTunnelAncestry(generic))
        #expect(USBTreeBuilder.pcieIndex(generic) == 3)
        #expect(!USBTreeBuilder.hasTunnelAncestry(native))
        #expect(!USBTreeBuilder.hasTunnelAncestry(embedded))
        #expect(!USBTreeBuilder.hasTunnelAncestry([RawAncestor(id: 1, className: "AppleUSBXHCIARM", name: "x")]))
    }

    @Test func ambiguousNamesStayAtPortLevel() throws {
        let host = F.tbSwitch(id: 1, depth: 0, ports: [F.lane(id: 2, portNumber: 1, socket: "1", speed: 0x4, width: 0x2)],
                              ancestry: F.hostAncestry(acio: 0))
        let first = F.tbSwitch(id: 3, parent: 1, depth: 1, uid: 3, model: "Pro Dock", ports: [],
                               ancestry: [RawAncestor(id: 2, className: "IOThunderboltPort", name: "IOThunderboltPort")])
        let second = F.tbSwitch(id: 4, parent: 3, depth: 2, uid: 4, model: "Pro Dock", ports: [])
        let raw = F.raw(ports: [F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"])],
                        usb: [F.usb(id: 20, name: "Pro Dock", location: 0x0510_0000,
                                    ancestry: F.tunnelAncestry(pcie: 0))],
                        thunderbolt: [host, first, second])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.devices.map(\.bus) == [.thunderbolt, .usb])
        #expect(port.devices.first?.children.map(\.name) == ["Pro Dock"])
        #expect(port.devices.first?.children.first?.bus == .thunderbolt)
    }

    @Test func orphanSwitchFindsItsHostThroughACIO() throws {
        let host = F.tbSwitch(id: 1, depth: 0, ports: [F.lane(id: 2, portNumber: 1, socket: "4", speed: 0x4, width: 0x2)],
                              ancestry: F.hostAncestry(acio: 3))
        let orphan = F.tbSwitch(id: 5, parent: 99, depth: 2, uid: 5, vendor: "Acme", model: nil,
                                ancestry: F.hostAncestry(acio: 3))
        let unplaced = F.tbSwitch(id: 6, parent: 98, depth: 1, uid: 6, model: "Lost Device")
        let raw = F.raw(ports: [F.port(id: 10, number: 4, connected: true, active: ["CC", "CIO"])],
                        thunderbolt: [host, orphan, unplaced])
        let snapshot = TopologyBuilder.build(raw)
        let port = try #require(snapshot.ports.first)
        #expect(port.devices.map(\.name) == ["Acme Thunderbolt Device"])
        #expect(port.devices.first?.chainDepth == 2)
        #expect(snapshot.otherDevices.map(\.name) == ["Lost Device"])
    }

    @Test func hostWithoutDepthOrParentIsARoot() throws {
        var host = F.tbSwitch(id: 1, depth: 0, ports: [F.lane(id: 2, portNumber: 1, socket: "1", speed: 0x4, width: 0x2)])
        host.node.properties["Depth"] = nil
        let child = F.tbSwitch(id: 3, parent: 1, depth: 1, uid: 0x10, model: "Thunderbolt 4 Hub",
                               ports: [F.adapter(id: 4, portNumber: 5, description: "USB Adapter", hops: true)])
        let raw = F.raw(ports: [F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"])],
                        thunderbolt: [host, child])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.devices.map(\.name) == ["Thunderbolt 4 Hub"])
        #expect(port.devices.first?.kind == .dock)
        // No ancestry entry for the host lane: the switch's own upstream lane is unknown.
        #expect(port.devices.first?.link == nil)
        #expect(port.link?.bitsPerSecond == 40_000_000_000)
    }

    @Test func liveUSBTunnelMarksAnAnonymousDeviceAsADock() throws {
        let host = F.tbSwitch(id: 1, depth: 0, ports: [F.lane(id: 2, portNumber: 1, socket: "1", speed: 0x4, width: 0x2)],
                              ancestry: F.hostAncestry(acio: 0))
        let device = F.tbSwitch(id: 3, parent: 1, depth: 1, uid: 3, vendor: "Acme", model: "Model X",
                                ports: [F.adapter(id: 4, portNumber: 9, description: "USB Adapter", hops: true),
                                        F.adapter(id: 5, portNumber: 8, description: "PCIe Adapter", hops: true)])
        func build(tunnelledUSB3: Bool) -> PhysicalPort? {
            var ports = [F.port(id: 10, number: 1, connected: true, active: ["CC", "CIO"]),
                         F.transport(id: 11, parent: 10, kind: "CIO", portNumber: 1)]
            if tunnelledUSB3 {
                ports.append(F.transport(id: 12, parent: 11, kind: "USB3", portNumber: 1, tunneled: true))
            }
            return TopologyBuilder.build(F.raw(ports: ports, thunderbolt: [host, device])).ports.first
        }
        #expect(build(tunnelledUSB3: true)?.devices.first?.kind == .dock)
        #expect(build(tunnelledUSB3: false)?.devices.first?.kind == .thunderboltDevice)
        // Tunnelled transports never become the port's own.
        #expect(build(tunnelledUSB3: true)?.activeTransports.map(\.kind) == [.cio])
    }

    @Test func tunnelledTransportsAloneMeanConnected() throws {
        var port = F.port(id: 10, number: 1, connected: false, active: [])
        port.properties["TransportsActive"] = nil
        let raw = F.raw(ports: [port, F.transport(id: 12, parent: 10, kind: "USB3", portNumber: 1, tunneled: true)])
        let result = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(result.isConnected)
        #expect(result.activeTransports.isEmpty)
    }

    @Test func modelNameCleanup() {
        #expect(ThunderboltParser.modelName("Other World Computing Other World Computing Envoy",
                                            vendor: "Other World Computing") == "Other World Computing Envoy")
        #expect(ThunderboltParser.modelName("OWC Envoy", vendor: "OWC") == "OWC Envoy")
        #expect(ThunderboltParser.modelName("OWC OWC", vendor: "OWC") == "OWC")
        #expect(ThunderboltParser.modelName("Ugreen Ugreen Revodok") == "Ugreen Revodok")
        #expect(ThunderboltParser.modelName("  Studio Display ") == "Studio Display")
        #expect(ThunderboltParser.modelName("") == nil)
        #expect(ThunderboltParser.modelName(nil) == nil)
    }
}
