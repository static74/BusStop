import Foundation
import Testing
@testable import BusStopCore

@Suite("Device identity")
struct DeviceIdentityTests {
    typealias F = HealthFixtures

    private func keys(_ ports: [PhysicalPort]) -> [String: String] {
        var shared = Set<String>()
        return DeviceIdentity.keys(in: F.snapshot(0, ports), sharedSerials: &shared)
    }

    @Test func serialSurvivesAControllerChange() {
        let fast = F.drive(location: 0x0110_0000)
        let slow = F.drive(location: 0x0010_0000, bps: 480_000_000, version: "2.1")
        #expect(fast.id != slow.id)
        let before = keys([F.port(1, [fast])])[fast.id]
        let after = keys([F.port(1, [slow])])[slow.id]
        #expect(before == "usb:04e8:61fb:S6XNNS0W123456")
        #expect(before == after)
    }

    @Test func serialLessDeviceUsesPortAndRoute() {
        let keyboard = F.usb("Keyboard", location: 0x0114_0000, kind: .keyboard, vendorID: 0x05ac, productID: 0x024f)
        #expect(keys([F.port(1, [keyboard])])[keyboard.id] == "usb:05ac:024f@2/1/140000")
        // A zero serial is no serial.
        let zeroed = F.usb("Keyboard", location: 0x0114_0000, serial: "0000", kind: .keyboard)
        #expect(keys([F.port(1, [zeroed])])[zeroed.id] == "usb:04e8:61fb@2/1/140000")
    }

    @Test func duplicateSerialsFallBackToPortAndRoute() {
        let a = F.usb("Stick", location: 0x0111_0000, serial: "123456789")
        let b = F.usb("Stick", location: 0x0112_0000, serial: "123456789")
        let hub = F.usb("USB3.1 Hub", location: 0x0110_0000, kind: .hub, children: [a, b])
        let result = keys([F.port(1, [hub])])
        #expect(result[a.id] == "usb:04e8:61fb@2/1/110000")
        #expect(result[b.id] == "usb:04e8:61fb@2/1/120000")
    }

    @Test func hubKeepsItsKeyWhenItLosesItsSuperSpeedHalf() {
        let merged = F.usb("USB3.1 Hub", location: 0x0110_0000, kind: .hub, vendorID: 0x2109, productID: 0x0817)
        let usb2Half = F.usb("USB2.1 Hub", location: 0x0010_0000, bps: 480_000_000, version: "2.1", kind: .hub,
                             vendorID: 0x2109, productID: 0x2817)
        let before = keys([F.port(1, [merged])])[merged.id]
        #expect(before == "hub:2109:hub@2/1/0")
        #expect(keys([F.port(1, [usb2Half])])[usb2Half.id] == before)
    }

    @Test func twoIdenticalHubsOnOnePortHaveNoKey() {
        let a = F.usb("USB2.0 Hub", location: 0x0111_0000, kind: .hub)
        let b = F.usb("USB2.0 Hub", location: 0x0112_0000, kind: .hub)
        let root = F.usb("Dock Hub", location: 0x0110_0000, kind: .hub, vendorID: 0x1234, children: [a, b])
        let result = keys([F.port(1, [root])])
        #expect(result[a.id] == nil)
        #expect(result[b.id] == nil)
        #expect(result[root.id] != nil)
    }

    @Test func thunderboltUsesItsUID() {
        let dock = DeviceNode(id: "tb:5a1c0ffee", bus: .thunderbolt, kind: .dock, name: "TS4")
        #expect(keys([F.port(1, [dock])])[dock.id] == "tb:5a1c0ffee")
    }

    @Test func builtInPartsHaveKeys() {
        let part = F.usb("Dock USB Hub", location: 0x0111_0000, kind: .hub, vendorID: 0x1234)
        let dock = DeviceNode(id: "tb:d0c", bus: .thunderbolt, kind: .dock, name: "Dock", internalParts: [part])
        let result = keys([F.port(1, [dock])])
        #expect(result[part.id] == "hub:1234:dock hub@2/1/1")
        #expect(result[dock.id] == "tb:d0c")
    }
}
