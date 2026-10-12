import Foundation
import Testing
@testable import BusStopCore

@Suite("Topology: USB devices")
struct USBTopologyTests {
    typealias F = TopologyFixtures

    static let twoPorts = [F.port(id: 1, number: 1, connected: true, active: ["CC", "USB2", "USB3"]),
                           F.port(id: 2, number: 2, connected: true, active: ["CC", "USB2", "USB3"]),
                           F.transport(id: 21, parent: 2, kind: "USB2", portNumber: 2)]

    // MARK: Attribution

    @Test func attributionOrder() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            // (a) UsbIOPort path wins over a contradicting drd number.
            F.usb(id: 100, name: "By Path", location: 0x0110_0000,
                  path: "IOService:/AppleARMPE/arm-io/AppleHPMDevice@3F/Port-USB-C@2", drd: 1),
            // (b) IOPort-plane transport parent.
            F.usb(id: 101, name: "By Transport", location: 0x0120_0000, ioPortParent: 21),
            // (d) usb-drdN port-number.
            F.usb(id: 102, name: "By DRD", location: 0x0210_0000, drd: 1),
            // (e) nothing usable.
            F.usb(id: 103, name: "Nowhere", location: 0x0310_0000, drd: 7),
        ])
        let snapshot = TopologyBuilder.build(raw)
        let port1 = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        let port2 = try #require(snapshot.port(PortKey(type: 2, number: 2)))
        #expect(port1.devices.map(\.name) == ["By DRD"])
        #expect(port2.devices.map(\.name) == ["By Path", "By Transport"])
        #expect(snapshot.otherDevices.map(\.name) == ["Nowhere"])
    }

    @Test func childrenInheritTheirRootsPort() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 10, name: "USB2.0 Hub", vendor: 0x05E3, location: 0x0110_0000, deviceClass: 9,
                  path: "x/Port-USB-C@1"),
            // The child's own (wrong) hints are ignored; it sits under its hub.
            F.usb(id: 11, parent: 10, name: "Mouse", location: 0x0111_0000, drd: 2,
                  interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1, interfaceProtocol: 2)]),
        ])
        let port1 = try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 1)))
        #expect(port1.devices.count == 1)
        #expect(port1.devices.first?.kind == .hub)
        #expect(port1.devices.first?.children.map(\.name) == ["Mouse"])
        #expect(port1.devices.first?.children.first?.kind == .mouse)
        #expect(port1.deviceCount == 2)
    }

    @Test func missingParentMakesARoot() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 11, parent: 999, name: "Orphan", location: 0x0111_0000, path: "x/Port-USB-C@1"),
        ])
        let port1 = try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 1)))
        #expect(port1.devices.map(\.name) == ["Orphan"])
    }

    @Test func deviceFieldsAndFallbacks() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 0x55, name: "", vendor: 0x05AC, product: 0x1460, location: nil, speed: nil, allocation: nil,
                  bcdUSB: 0x0320, vendorName: "xxxxxxxx", path: "x/Port-USB-C@1",
                  extra: ["USB Product Name": "xxxxxxxx", "Device Speed": 3, "Requested Power": 50,
                          "kUSBSerialNumberString": "ABC123"]),
        ])
        let device = try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 1))?.devices.first)
        // No usable product name: the registry name is empty too, so a generic name.
        #expect(device.name == "USB Device 0x1460")
        #expect(device.vendorName == nil)
        #expect(device.serialNumber == "ABC123")
        #expect(device.id == "usb:reg-55:05ac:1460")
        #expect(device.locationID == nil)
        #expect(device.usbVersion == "3.2")
        #expect(device.link?.label == "USB 3.2 Gen 1 @ 5 Gb/s")
        // Requested Power is in units of 2 mA: 50 → 100 mA → 500 mW.
        #expect(device.power?.allocatedMilliwatts == 500)
    }

    // MARK: Hubs

    @Test func usb3HubAndItsCompanionMerge() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 30, name: "USB3.0 Hub", vendor: 0x2109, product: 0x0817, location: 0x0120_0000,
                  speed: 5_000_000_000, allocation: 0, deviceClass: 9, bcdUSB: 0x0320, path: "x/Port-USB-C@1"),
            F.usb(id: 31, name: "USB2.0 Hub", vendor: 0x2109, product: 0x2817, location: 0x0110_0000,
                  speed: 480_000_000, allocation: 100, deviceClass: 9, bcdUSB: 0x0210, path: "x/Port-USB-C@1"),
            F.usb(id: 32, parent: 30, name: "Portable SSD", location: 0x0121_0000, speed: 10_000_000_000,
                  allocation: 896, interfaces: [RawUSBInterface(interfaceClass: 8)]),
            F.usb(id: 33, parent: 31, name: "Keyboard", location: 0x0112_0000, allocation: 100,
                  interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1, interfaceProtocol: 1)]),
            // A USB 2 hub of another vendor stays separate.
            F.usb(id: 34, name: "USB2.0 Hub", vendor: 0x1A40, product: 0x0101, location: 0x0130_0000,
                  deviceClass: 9, path: "x/Port-USB-C@1"),
        ])
        let port = try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 1)))
        #expect(port.devices.count == 2)
        let hub = try #require(port.devices.first { $0.vendorID == 0x2109 })
        #expect(hub.id == "usb:01200000:2109:0817")
        #expect(hub.name == "USB3.0 Hub")
        #expect(hub.link?.bitsPerSecond == 5_000_000_000)
        #expect(hub.children.map(\.name) == ["Keyboard", "Portable SSD"])
        // Both halves share one upstream connection: the larger allocation counts.
        #expect(hub.power?.allocatedMilliwatts == 500)
        #expect(hub.rolledUpMilliwatts == 500 + 4480 + 500)
        #expect(port.allocatedMilliwatts == 500 + 4480 + 500 + 500)
    }

    @Test func nestedCompanionPairsMergeToo() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 40, name: "USB3 Hub", vendor: 0x2109, location: 0x0120_0000, speed: 5_000_000_000,
                  deviceClass: 9, path: "x/Port-USB-C@2"),
            F.usb(id: 41, name: "USB2 Hub", vendor: 0x2109, location: 0x0110_0000, deviceClass: 9,
                  path: "x/Port-USB-C@2"),
            F.usb(id: 42, parent: 40, name: "USB3.1 Hub", vendor: 0x05E3, location: 0x0124_0000,
                  speed: 10_000_000_000, deviceClass: 9),
            F.usb(id: 43, parent: 41, name: "USB2.1 Hub", vendor: 0x05E3, location: 0x0114_0000, deviceClass: 9),
            F.usb(id: 44, parent: 43, name: "Webcam", location: 0x0114_1000,
                  interfaces: [RawUSBInterface(interfaceClass: 14)]),
        ])
        let port = try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 2)))
        #expect(port.devices.count == 1)
        let outer = try #require(port.devices.first)
        #expect(outer.children.count == 1)
        let inner = try #require(outer.children.first)
        #expect(inner.name == "USB3.1 Hub")
        #expect(inner.children.map(\.name) == ["Webcam"])
        #expect(inner.children.first?.kind == .camera)
    }

    @Test func selfPoweredHubRollUp() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 50, name: "Powered Hub", vendor: 0x2001, location: 0x0110_0000, allocation: 100,
                  deviceClass: 9, path: "x/Port-USB-C@1", extra: ["kUSBHubPowerSupply": 3000]),
            F.usb(id: 51, parent: 50, name: "Drive A", location: 0x0111_0000, allocation: 900),
            F.usb(id: 52, parent: 50, name: "Drive B", location: 0x0112_0000, allocation: 900),
            F.usb(id: 60, name: "Bus Hub", vendor: 0x2002, location: 0x0210_0000, allocation: 100,
                  deviceClass: 9, path: "x/Port-USB-C@2", extra: ["kUSBHubPowerSupplyType": 2]),
            F.usb(id: 61, parent: 60, name: "Drive C", location: 0x0211_0000, allocation: 900),
        ])
        let snapshot = TopologyBuilder.build(raw)
        let powered = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        let poweredHub = try #require(powered.devices.first)
        #expect(poweredHub.power?.isSelfPowered == true)
        #expect(poweredHub.rolledUpMilliwatts == 500)
        #expect(poweredHub.downstreamMilliwatts == 9000)
        #expect(powered.allocatedMilliwatts == 500)
        #expect(powered.power?.milliwatts == 500)
        #expect(powered.power?.source == .usbAllocation)

        let bus = try #require(snapshot.port(PortKey(type: 2, number: 2)))
        #expect(bus.devices.first?.power?.isSelfPowered == false)
        #expect(bus.allocatedMilliwatts == 500 + 4500)
        #expect(snapshot.power.usbAllocatedMilliwatts == 500 + 5000)
        #expect(snapshot.power.portOutputMilliwatts == 500 + 5000)
    }

    @Test func supplyTypeOneMeansSelfPowered() {
        #expect(USBTreeBuilder.power(["kUSBHubPowerSupplyType": 1])?.isSelfPowered == true)
        #expect(USBTreeBuilder.power(["kUSBHubPowerSupply": 0])?.isSelfPowered == false)
        #expect(USBTreeBuilder.power(["UsbPowerSinkAllocation": 500])?.isSelfPowered == nil)
        #expect(USBTreeBuilder.power([:]) == nil)
        #expect(USBTreeBuilder.power(["UsbPowerSinkAllocation": -5]) == nil)
    }

    @Test func dockHub() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 70, name: "Docking Station Hub", vendor: 0x2188, location: 0x0110_0000, deviceClass: 9,
                  path: "x/Port-USB-C@1"),
            F.usb(id: 71, parent: 70, name: "USB 10/100/1000 LAN", vendor: 0x0BDA, location: 0x0111_0000,
                  interfaces: [RawUSBInterface(interfaceClass: 0xFF)]),
        ])
        let device = try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 1))?.devices.first)
        #expect(device.kind == .dock)
        #expect(device.children.first?.kind == .network)
    }

    // MARK: Filtering

    @Test func internalAndUnattributedDevices() throws {
        let auss = [RawAncestor(id: 900, className: "AppleT6050USBXHCIAUSS", name: "AppleT6050USBXHCIAUSS"),
                    RawAncestor(id: 901, className: "AppleARMIODevice", name: "usb-auss0")]
        let raw = F.raw(ports: Self.twoPorts, usb: [
            // Behind the internal controller: dropped with its children.
            F.usb(id: 1, name: "Internal Hub", vendor: 0x1111, location: 0x0A10_0000, deviceClass: 9, ancestry: auss),
            F.usb(id: 2, parent: 1, name: "Sensor", vendor: 0x1111, location: 0x0A11_0000),
            // Apple-internal names, unattributed: dropped.
            F.usb(id: 3, name: "FaceTime HD Camera", vendor: 0x05AC, location: 0x0B10_0000),
            F.usb(id: 4, name: "Apple Internal Keyboard / Trackpad", vendor: 0x05AC, location: 0x0B20_0000),
            F.usb(id: 5, name: "Touch Bar Display", vendor: 0x05AC, location: 0x0B30_0000),
            // Internal hub persona: removed, external child kept.
            F.usb(id: 6, name: "Hub", vendor: 0x05E3, location: 0x0C10_0000, deviceClass: 9,
                  extra: ["USBPortType": 2]),
            F.usb(id: 7, parent: 6, name: "Wireless Receiver", vendor: 0x046D, location: 0x0C11_0000),
            // Plain unattributed external device: listed under other devices.
            F.usb(id: 8, name: "Serial Adapter", vendor: 0x0403, location: 0x0D10_0000),
            // An Apple device on a real port is never dropped.
            F.usb(id: 9, name: "Apple Internal Thing", vendor: 0x05AC, location: 0x0110_0000, path: "x/Port-USB-C@1"),
        ])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.otherDevices.map(\.name) == ["Serial Adapter", "Wireless Receiver"])
        #expect(snapshot.port(PortKey(type: 2, number: 1))?.devices.map(\.name) == ["Apple Internal Thing"])
        #expect(!snapshot.allDevices.contains { $0.device.name == "Sensor" })
    }

    @Test func parentCyclesDoNotLoseOrDuplicateDevices() {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 1, parent: 2, name: "A", location: 0x0110_0000, path: "x/Port-USB-C@1"),
            F.usb(id: 2, parent: 1, name: "B", location: 0x0111_0000, path: "x/Port-USB-C@1"),
            F.usb(id: 3, parent: 3, name: "Self", location: 0x0112_0000, path: "x/Port-USB-C@1"),
        ])
        let snapshot = TopologyBuilder.build(raw)
        let names = snapshot.allDevices.map(\.device.name).sorted()
        #expect(names == ["A", "B", "Self"])
    }

    @Test func duplicateIDsAreMadeUnique() {
        // Two captures of the same location: IDs must still be unique.
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 1, name: "Twin", location: 0x0110_0000, path: "x/Port-USB-C@1"),
            F.usb(id: 2, name: "Twin", location: 0x0110_0000, path: "x/Port-USB-C@2"),
        ])
        let ids = TopologyBuilder.build(raw).allDevices.map(\.device.id)
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(ids.contains("usb:01100000:1234:5678"))
    }

    @Test func devicesAreSortedByNameThenID() throws {
        let raw = F.raw(ports: Self.twoPorts, usb: [
            F.usb(id: 1, name: "zeta", location: 0x0110_0000, path: "x/Port-USB-C@1"),
            F.usb(id: 2, name: "Alpha", location: 0x0120_0000, path: "x/Port-USB-C@1"),
            F.usb(id: 3, name: "beta", location: 0x0130_0000, path: "x/Port-USB-C@1"),
            F.usb(id: 4, name: "Alpha", location: 0x0105_0000, path: "x/Port-USB-C@1"),
        ])
        let port = try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 1)))
        #expect(port.devices.map(\.name) == ["Alpha", "Alpha", "beta", "zeta"])
        #expect(port.devices.prefix(2).map(\.id) == ["usb:01050000:1234:5678", "usb:01200000:1234:5678"])
    }
}
