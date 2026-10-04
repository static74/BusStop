import Foundation
import Testing
@testable import BusStopCore

/// USB 3 hubs and their USB 2 companions: a pair is merged only when the two
/// halves sit on the same downstream port, so an unrelated USB 2 hub of the
/// same vendor (VIA calls both "USB2.0 Hub") keeps its own devices.
@Suite("Topology: USB companion hubs")
struct CompanionHubTests {
    typealias F = TopologyFixtures

    static let port = [F.port(id: 1, number: 1, connected: true, active: ["CC", "USB2", "USB3"])]

    /// A parent hub with both halves on root ports 1 (SuperSpeed) and 2
    /// (USB 2); below it a USB 3 hub with both halves on downstream port
    /// `pairPort`, and a USB 2-only hub of the same vendor on `otherPort`
    /// with a keyboard.
    static func raw(pairPort: UInt32, otherPort: UInt32) -> RawSnapshot {
        F.raw(ports: port, usb: [
            F.usb(id: 10, name: "USB3.0 Hub", vendor: 0x2109, product: 0x0817, location: 0x0110_0000,
                  speed: 5_000_000_000, deviceClass: 9, bcdUSB: 0x0320, path: "x/Port-USB-C@1"),
            F.usb(id: 11, name: "USB2.0 Hub", vendor: 0x2109, product: 0x2817, location: 0x0120_0000,
                  deviceClass: 9, bcdUSB: 0x0210, path: "x/Port-USB-C@1"),
            // The child hub's two halves.
            F.usb(id: 20, parent: 10, name: "USB3.0 Hub", vendor: 0x2109, product: 0x0817,
                  location: 0x0110_0000 | (pairPort << 16), speed: 5_000_000_000, deviceClass: 9, bcdUSB: 0x0320),
            F.usb(id: 21, parent: 11, name: "USB2.0 Hub", vendor: 0x2109, product: 0x2817,
                  location: 0x0120_0000 | (pairPort << 16), deviceClass: 9, bcdUSB: 0x0210),
            F.usb(id: 22, parent: 21, name: "Webcam", location: 0x0120_0000 | (pairPort << 16) | 0x1000,
                  interfaces: [RawUSBInterface(interfaceClass: 14)]),
            // A separate USB 2-only hub of the same vendor and name.
            F.usb(id: 30, parent: 11, name: "USB2.0 Hub", vendor: 0x2109, product: 0x2817,
                  location: 0x0120_0000 | (otherPort << 16), deviceClass: 9, bcdUSB: 0x0210),
            F.usb(id: 31, parent: 30, name: "Keyboard", location: 0x0120_0000 | (otherPort << 16) | 0x1000,
                  interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1, interfaceProtocol: 1)]),
        ])
    }

    static func check(pairPort: UInt32, otherPort: UInt32) throws {
        let port = try #require(TopologyBuilder.build(raw(pairPort: pairPort, otherPort: otherPort))
            .port(PortKey(type: 2, number: 1)))
        #expect(port.devices.count == 1)
        let parent = try #require(port.devices.first)
        #expect(parent.children.count == 2)
        // The USB 3 hub absorbed only the companion on its own port.
        let pair = try #require(parent.children.first { $0.link?.bitsPerSecond == 5_000_000_000 })
        #expect(pair.children.map(\.name) == ["Webcam"])
        #expect(USBTreeBuilder.tierPort(pair.locationID) == pairPort)
        // The keyboard stays under its own USB 2 hub.
        let other = try #require(parent.children.first { $0.link?.bitsPerSecond == 480_000_000 })
        #expect(other.children.map(\.name) == ["Keyboard"])
        #expect(USBTreeBuilder.tierPort(other.locationID) == otherPort)
    }

    @Test func pairOnPortFourIgnoresTheHubOnPortOne() throws {
        // Scenario A: the stray hub has the lower location ID.
        try Self.check(pairPort: 4, otherPort: 1)
    }

    @Test func pairOnPortThreeIgnoresTheHubOnPortFour() throws {
        // Scenario B: the stray hub has the higher location ID.
        try Self.check(pairPort: 3, otherPort: 4)
    }

    @Test func ambiguousRootHubsStaySeparate() throws {
        // Scenario C: a USB 3 hub and two same-named USB 2 hubs of its vendor
        // on the port itself. Either could be the companion, so neither is.
        let raw = F.raw(ports: Self.port, usb: [
            F.usb(id: 10, name: "USB3.0 Hub", vendor: 0x2109, location: 0x0110_0000, speed: 5_000_000_000,
                  deviceClass: 9, path: "x/Port-USB-C@1"),
            F.usb(id: 11, name: "USB2.0 Hub", vendor: 0x2109, location: 0x0120_0000, deviceClass: 9,
                  path: "x/Port-USB-C@1"),
            F.usb(id: 12, name: "USB2.0 Hub", vendor: 0x2109, location: 0x0130_0000, deviceClass: 9,
                  path: "x/Port-USB-C@1"),
        ])
        let port = try #require(TopologyBuilder.build(raw).port(PortKey(type: 2, number: 1)))
        #expect(port.devices.count == 3)
    }

    @Test func tierHelpers() {
        #expect(USBTreeBuilder.tierPort(0x0114_0000) == 4)
        #expect(USBTreeBuilder.tierPort(0x0110_0000) == 1)
        #expect(USBTreeBuilder.tierPort(0x0114_3200) == 2)
        #expect(USBTreeBuilder.tierPort(0x0100_0000) == nil)
        #expect(USBTreeBuilder.tierPort(nil) == nil)
        #expect(USBTreeBuilder.tierDepth(0x0114_0000) == 2)
        #expect(USBTreeBuilder.tierDepth(0x0114_3200) == 4)
        #expect(USBTreeBuilder.tierDepth(0x0100_0000) == 0)
    }
}
