import Foundation
import Testing
@testable import BusStopCore

@Suite("Snapshot differ")
struct SnapshotDifferTests {
    typealias F = SupportFixtures

    private let later = SupportFixtures.date.addingTimeInterval(2.5)
    private var stamp: Int64 { Int64(later.timeIntervalSince1970 * 1000) }

    private func diff(_ old: HostSnapshot?, _ new: HostSnapshot) -> [ConnectionEvent] {
        SnapshotDiffer.events(from: old, to: new, at: later)
    }

    private func t9(bps: Int64 = 10_000_000_000) -> DeviceNode {
        F.usbDevice("usb:t9", "Samsung T9", bps: bps, milliwatts: 4_500)
    }

    private func hubWithThreeDevices() -> DeviceNode {
        F.hub("usb:hub", "USB hub", children: [
            F.usbDevice("usb:kb", "Keyboard", kind: .keyboard, bps: 12_000_000, usbVersion: "2.0"),
            F.usbDevice("usb:inner", "Inner hub", kind: .hub, bps: 480_000_000, usbVersion: "2.0", children: [
                F.usbDevice("usb:mouse", "Mouse", kind: .mouse, bps: 12_000_000, usbVersion: "2.0"),
            ]),
        ])
    }

    @Test func firstCaptureHasNoEvents() {
        #expect(diff(nil, F.studioDesk()).isEmpty)
        #expect(diff(F.studioDesk(), F.studioDesk()).isEmpty)
    }

    @Test func deviceConnected() throws {
        let old = F.snapshot(ports: [F.usbC(2, "Left Front")])
        let new = F.snapshot(ports: [F.usbC(2, "Left Front", devices: [t9()])])
        let events = diff(old, new)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.kind == .deviceConnected)
        #expect(event.title == "Samsung T9 connected")
        #expect(event.detail == "Left Front · USB-C · USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(event.portKey == PortKey(type: 2, number: 2))
        #expect(event.deviceID == "usb:t9")
        #expect(event.id == "deviceConnected:usb:t9:\(stamp)")
        #expect(event.date == later)
    }

    @Test func hubDisconnectCollapsesToOneEvent() throws {
        let old = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [hubWithThreeDevices()])])
        let new = F.snapshot(ports: [F.usbC(1, "Left Center")])
        let events = diff(old, new)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.kind == .deviceDisconnected)
        #expect(event.title == "USB hub disconnected")
        #expect(event.detail.contains("and 3 more devices"))
        #expect(event.detail.hasPrefix("Left Center · USB-C"))
        #expect(event.deviceID == "usb:hub")
    }

    @Test func hubConnectCountsOnlyNewDevices() throws {
        // The keyboard was already known on another port; it moved under the new hub.
        let keyboard = F.usbDevice("usb:kb", "Keyboard", kind: .keyboard, bps: 12_000_000, usbVersion: "2.0")
        let old = F.snapshot(ports: [F.usbC(1, "Left Center"), F.usbC(2, "Left Front", devices: [keyboard])])
        let new = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [hubWithThreeDevices()]), F.usbC(2, "Left Front")])
        let events = diff(old, new)
        #expect(events.map(\.kind) == [.deviceConnected])
        #expect(events.first?.detail.hasSuffix("and 2 more devices") == true)
    }

    @Test func singleExtraDeviceIsSingular() {
        let hub = F.hub("usb:hub", children: [F.usbDevice("usb:a", "Drive", bps: 5_000_000_000)])
        let events = diff(F.snapshot(ports: [F.usbC(1, "Left Center")]),
                          F.snapshot(ports: [F.usbC(1, "Left Center", devices: [hub])]))
        #expect(events.first?.detail.hasSuffix("and 1 more device") == true)
    }

    @Test func childDisconnectUnderRemainingHub() {
        let hub = hubWithThreeDevices()
        var trimmed = hub
        trimmed.children.removeFirst()
        let events = diff(F.snapshot(ports: [F.usbC(1, "Left Center", devices: [hub])]),
                          F.snapshot(ports: [F.usbC(1, "Left Center", devices: [trimmed])]))
        #expect(events.map(\.title) == ["Keyboard disconnected"])
    }

    @Test func movingBetweenPortsIsNotAConnection() {
        let old = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [t9()]), F.usbC(2, "Left Front")])
        let new = F.snapshot(ports: [F.usbC(1, "Left Center"), F.usbC(2, "Left Front", devices: [t9()])])
        #expect(diff(old, new).isEmpty)

        let unattributed = F.snapshot(otherDevices: [t9()])
        #expect(diff(old, unattributed).isEmpty)
    }

    @Test func unattributedDeviceDetailFallsBackToLink() throws {
        let events = diff(F.snapshot(), F.snapshot(otherDevices: [t9()]))
        let event = try #require(events.first)
        #expect(event.detail == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(event.portKey == nil)
    }

    @Test func linkDowngradeAndUpgrade() throws {
        let fast = F.snapshot(ports: [F.usbC(2, "Left Front", devices: [t9()])])
        let slow = F.snapshot(ports: [F.usbC(2, "Left Front", devices: [t9(bps: 480_000_000)])])

        let down = try #require(diff(fast, slow).first)
        #expect(down.kind == .linkChanged)
        #expect(down.isDowngrade)
        #expect(down.title == "Samsung T9 slowed down")
        #expect(down.detail == "Left Front · USB-C · USB 3.2 Gen 2 @ 10 Gb/s → USB 2.0 @ 480 Mb/s")
        #expect(down.id == "linkChanged:usb:t9:\(stamp)")
        #expect(down.symbolName == "arrow.down.circle")

        let up = try #require(diff(slow, fast).first)
        #expect(!up.isDowngrade)
        #expect(up.title == "Samsung T9 sped up")

        // An unknown rate on either side is not a change.
        var unknown = t9()
        unknown.link = nil
        #expect(diff(fast, F.snapshot(ports: [F.usbC(2, "Left Front", devices: [unknown])])).isEmpty)
    }

    @Test func chargerEvents() throws {
        let charger = F.charger(name: "96W USB-C Power Adapter")
        let none = F.snapshot(ports: [F.magSafe()])
        let plugged = F.snapshot(ports: [F.magSafe(charger: charger)], power: PowerSummary(charger: charger))

        let connected = try #require(diff(none, plugged).first)
        #expect(connected.kind == .chargerConnected)
        #expect(connected.title == "96W USB-C Power Adapter connected")
        #expect(connected.detail == "Left Rear · MagSafe · 20 V × 4.7 A · 96 W")
        #expect(connected.id == "chargerConnected:charger:\(stamp)")
        #expect(connected.portKey == PortKey(type: 17, number: 1))

        let disconnected = try #require(diff(plugged, none).first)
        #expect(disconnected.kind == .chargerDisconnected)
        #expect(disconnected.title == "96W USB-C Power Adapter disconnected")

        let other = F.charger(name: "30W USB-C Power Adapter", watts: 30)
        let swapped = F.snapshot(ports: [F.magSafe(charger: other)], power: PowerSummary(charger: other))
        let changed = diff(plugged, swapped)
        #expect(changed.map(\.kind) == [.chargerConnected])
        #expect(changed.first?.title == "30W USB-C Power Adapter connected")
        #expect(changed.first?.detail.contains("replaces 96W USB-C Power Adapter") == true)

        // Same charger, new contract: nothing to report.
        var renegotiated = charger
        renegotiated.millivolts = 15_000
        #expect(diff(plugged, F.snapshot(ports: [F.magSafe(charger: renegotiated)],
                                         power: PowerSummary(charger: renegotiated))).isEmpty)
    }

    @Test func displayEvents() throws {
        let studio = DisplayInfo(id: "display:1552:41006:1", name: "Studio Display", isBuiltin: false, pixelWidth: 5120,
                                 pixelHeight: 2880, refreshHz: 60, portKey: PortKey(type: 2, number: 1))
        let builtin = DisplayInfo(id: "display:builtin", name: "Color LCD", isBuiltin: true)
        let ports = [F.usbC(1, "Left Center", connected: true)]
        let without = F.snapshot(ports: ports, displays: [builtin])
        let with = F.snapshot(ports: ports, displays: [builtin, studio])

        let connected = try #require(diff(without, with).first)
        #expect(connected.kind == .displayConnected)
        #expect(connected.title == "Studio Display connected")
        #expect(connected.detail == "Left Center · USB-C · 5120 × 2880 @ 60 Hz")
        #expect(connected.id == "displayConnected:display:1552:41006:1:\(stamp)")

        #expect(diff(with, without).map(\.kind) == [.displayDisconnected])
        // Closing the lid takes the built-in panel offline; that is not an event.
        #expect(diff(with, F.snapshot(ports: ports, displays: [studio])).isEmpty)
    }

    @Test func newDiagnosticsAreRaisedOnce() throws {
        let wet = Diagnostic(id: "liquidDetected:2/1", kind: .liquidDetected, severity: .critical,
                             title: "Liquid detected in Left Center · USB-C", detail: "Dry the port.",
                             portKey: PortKey(type: 2, number: 1))
        let slow = Diagnostic(id: "usb2Fallback:usb:t9", kind: .usb2Fallback, severity: .warning,
                              title: "Samsung T9 is running at USB 2 speed", detail: "…", deviceID: "usb:t9")
        let old = F.snapshot(diagnostics: [slow])
        let new = F.snapshot(diagnostics: [wet, slow])
        let events = diff(old, new)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.kind == .diagnosticRaised)
        #expect(event.title == wet.title)
        #expect(event.detail == wet.detail)
        #expect(event.id == "diagnosticRaised:liquidDetected:2/1:\(stamp)")
        #expect(event.portKey == wet.portKey)
        #expect(diff(new, old).isEmpty)
    }

    @Test func stableOrder() {
        let charger = F.charger()
        let display = DisplayInfo(id: "display:1", name: "Monitor", isBuiltin: false)
        let diagnostic = Diagnostic(id: "deepChain:tb:6", kind: .deepChain, severity: .info, title: "Deep", detail: "")
        let old = F.snapshot(ports: [
            F.usbC(1, "Left Center", devices: [F.usbDevice("usb:gone", "Old drive", bps: 5_000_000_000)]),
            F.usbC(2, "Left Front", devices: [t9()]),
        ])
        let new = F.snapshot(ports: [
            F.usbC(1, "Left Center", devices: [F.usbDevice("usb:new", "New drive", bps: 5_000_000_000)]),
            F.usbC(2, "Left Front", devices: [t9(bps: 5_000_000_000)]),
        ], displays: [display], power: PowerSummary(charger: charger), diagnostics: [diagnostic])
        let kinds = diff(old, new).map(\.kind)
        #expect(kinds == [.deviceDisconnected, .deviceConnected, .linkChanged, .chargerConnected, .displayConnected,
                          .diagnosticRaised])
        // Deterministic: the same input gives the same events.
        #expect(diff(old, new) == diff(old, new))
    }

    @Test func millisecondStamp() {
        #expect(SnapshotDiffer.milliseconds(Date(timeIntervalSince1970: 1.2346)) == 1235)
        #expect(SnapshotDiffer.milliseconds(Date(timeIntervalSince1970: 1_791_115_202.5)) == 1_791_115_202_500)
        #expect(SnapshotDiffer.milliseconds(Date(timeIntervalSince1970: 0)) == 0)
    }
}
