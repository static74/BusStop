import Foundation
@testable import BusStopCore

/// Hand-built devices and snapshots for the connection health tests.
enum HealthFixtures {
    static let start = SupportFixtures.date
    static let port1 = PortKey(type: PortKey.usbCType, number: 1)
    static let port2 = PortKey(type: PortKey.usbCType, number: 2)

    /// A USB device whose id embeds its `locationID`, as `USBTreeBuilder` builds it.
    static func usb(_ name: String, location: UInt32, serial: String? = nil, bps: Int64 = 10_000_000_000,
                    version: String = "3.2", kind: DeviceKind = .storage, vendorID: Int = 0x04e8,
                    productID: Int = 0x61fb, selfPowered: Bool? = nil, children: [DeviceNode] = []) -> DeviceNode {
        DeviceNode(id: "usb:\(String(format: "%08x", location)):\(String(format: "%04x", vendorID)):"
                       + String(format: "%04x", productID),
                   bus: .usb, kind: kind, name: name, vendorID: vendorID, productID: productID, serialNumber: serial,
                   usbVersion: version, deviceClass: kind == .hub ? 9 : 0, locationID: location,
                   link: SupportFixtures.usbLink(bps),
                   power: selfPowered.map { DevicePower(allocatedMilliwatts: nil, isSelfPowered: $0) },
                   children: children)
    }

    /// A Samsung T9 with a serial, at 10 Gb/s on the first USB 3 controller.
    static func drive(location: UInt32 = 0x0110_0000, bps: Int64 = 10_000_000_000,
                      version: String = "3.2") -> DeviceNode {
        usb("Samsung T9", location: location, serial: "S6XNNS0W123456", bps: bps, version: version)
    }

    static func port(_ number: Int, _ devices: [DeviceNode] = [], supported: [TransportKind] = [.usb2, .usb3, .cio],
                     plugEvents: Int? = nil, liquid: Bool = false) -> PhysicalPort {
        SupportFixtures.usbC(number, number == 1 ? "Left Rear" : "Left Front", supported: supported,
                             devices: devices, statistics: plugEvents.map { PortStatistics(plugEventCount: $0) },
                             liquid: liquid)
    }

    static func snapshot(_ seconds: TimeInterval, _ ports: [PhysicalPort]) -> HostSnapshot {
        HostSnapshot(capturedAt: start.addingTimeInterval(seconds), machine: SupportFixtures.laptop(), ports: ports)
    }
}

/// Feeds captures to a `ConnectionHealth`; the first one counts as after a gap.
struct HealthRun {
    var health = ConnectionHealth()
    var last: [Diagnostic] = []
    private var started = false

    @discardableResult
    mutating func observe(_ seconds: TimeInterval, _ ports: [PhysicalPort], afterGap: Bool = false) -> [Diagnostic] {
        last = health.observe(HealthFixtures.snapshot(seconds, ports), afterGap: afterGap || !started)
        started = true
        return last
    }

    /// Plugged in at `start`, then out and back in on `port` every 10 s, `times` times.
    /// Returns the time of the last return.
    @discardableResult
    mutating func cycle(_ device: DeviceNode, on port: Int, times: Int, from start: TimeInterval) -> TimeInterval {
        var t = start
        observe(t, [HealthFixtures.port(port, [device])])
        for _ in 0..<times {
            observe(t + 5, [HealthFixtures.port(port)])
            t += 10
            observe(t, [HealthFixtures.port(port, [device])])
        }
        return t
    }

    func kinds() -> [DiagnosticKind] { last.map(\.kind) }
}
