import Foundation
import Testing
@testable import BusStopCore

/// Regression tests for duplicate display events, Thunderbolt 5 Bandwidth
/// Boost read as a downgrade, diagnostic severity on events and names with
/// terminal control sequences.
@Suite("Snapshot differ: regressions")
struct SnapshotDifferRegressionTests {
    typealias F = SupportFixtures

    private let later = SupportFixtures.date.addingTimeInterval(2.5)

    private func diff(_ old: HostSnapshot, _ new: HostSnapshot) -> [ConnectionEvent] {
        SnapshotDiffer.events(from: old, to: new, at: later)
    }

    private static func build(_ raw: RawSnapshot) -> HostSnapshot {
        TopologyBuilder.build(raw, options: BuildOptions(isDemo: true))
    }

    private static func dockStation() -> RawSnapshot {
        DemoScenario.dockStation.raw(at: DemoTestSupport.date)
    }

    private static func studioDesk() -> RawSnapshot {
        DemoScenario.studioDesk.raw(at: DemoTestSupport.date)
    }

    // MARK: Displays

    @Test func displayRowGivesOneEventEachWay() {
        let display = DisplayInfo(id: "display:10ac:42b4:12345", name: "DELL U2723QE", vendorID: 0x10AC,
                                  productID: 0x42B4, serialNumber: 12345, isBuiltin: false, pixelWidth: 3840,
                                  pixelHeight: 2160, refreshHz: 60, portKey: PortKey(type: 2, number: 1))
        let attribution = DisplayParser.Attribution(portKey: PortKey(type: 2, number: 1), link: nil, isTunneled: false,
                                                    representedByThunderbolt: false)
        let row = DisplayParser.deviceNode(display, attribution: attribution)
        let without = F.snapshot(ports: [F.usbC(1, "Left Center", connected: true)])
        let with = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [row])], displays: [display])
        #expect(diff(without, with).map(\.kind) == [.displayConnected])
        #expect(diff(with, without).map(\.kind) == [.displayDisconnected])
    }

    @Test func hdmiPlugAndUnplugGiveOneEventEach() throws {
        var unplugged = Self.dockStation()
        unplugged.displays = []
        let with = Self.build(Self.dockStation())
        let without = Self.build(unplugged)
        // The display has a row on the HDMI port, so both paths could report it.
        #expect(with.port(PortKey(type: PortKey.hdmiType, number: 1))?.devices.map(\.kind) == [.display])

        let plugged = diff(without, with)
        #expect(plugged.map(\.kind) == [.displayConnected])
        let event = try #require(plugged.first)
        #expect(event.title == "LG UltraFine connected")
        #expect(event.subjectID == with.displays.first?.id)
        #expect(diff(with, without).map(\.kind) == [.displayDisconnected])
    }

    @Test func thunderboltDisplayUnplugGivesOneEvent() throws {
        var unplugged = Self.studioDesk()
        let uid = DemoStudioDesk.displayUID
        unplugged.thunderboltSwitches.removeAll { $0.node.properties.int64("UID") == uid }
        unplugged.displays.removeAll { !$0.isBuiltin }
        let with = Self.build(Self.studioDesk())
        let without = Self.build(unplugged)
        let display = try #require(with.displays.first { !$0.isBuiltin })
        #expect(display.representingDeviceID != nil)
        #expect(display.representingDeviceID == with.allDevices.first { $0.device.bus == .thunderbolt }?.device.id)

        let removed = diff(with, without).filter { $0.kind != .diagnosticRaised }
        #expect(removed.map(\.kind) == [.deviceDisconnected])
        #expect(removed.first?.title == "Studio Display XDR disconnected")
        #expect(removed.first?.deviceID == display.representingDeviceID)
        let added = diff(without, with).filter { $0.kind != .diagnosticRaised }
        #expect(added.map(\.kind) == [.deviceConnected])
    }

    @Test func secondUnattributedDisplayOnlyReportsItself() throws {
        var twoDisplays = Self.dockStation()
        twoDisplays.displays.append(RawDisplay(id: 9, name: "Sidecar Display", isBuiltin: false, pixelWidth: 2732,
                                               pixelHeight: 2048, refreshHz: 60))
        let before = Self.build(Self.dockStation())
        let after = Self.build(twoDisplays)
        // The LG's row leaves the HDMI port: two displays and one HDMI link
        // cannot be placed with confidence.
        #expect(after.port(PortKey(type: PortKey.hdmiType, number: 1))?.devices.isEmpty == true)

        let events = diff(before, after)
        #expect(events.map(\.kind) == [.displayConnected])
        #expect(events.first?.title == "Sidecar Display connected")
        #expect(diff(after, before).map(\.kind) == [.displayDisconnected])
    }

    // MARK: Links

    private func thunderboltDevice(_ link: LinkInfo) -> DeviceNode {
        DeviceNode(id: "tb:dock", bus: .thunderbolt, kind: .dock, name: "Dock", link: link)
    }

    private func linkDiff(_ old: LinkInfo, _ new: LinkInfo) -> [ConnectionEvent] {
        diff(F.snapshot(ports: [F.usbC(1, "Left Center", devices: [thunderboltDevice(old)])]),
             F.snapshot(ports: [F.usbC(1, "Left Center", devices: [thunderboltDevice(new)])]))
    }

    private static func tb(lanes: Int, gbps: Int64, asymmetric: Bool = false) -> LinkInfo {
        LinkInfo(family: .thunderbolt, generation: "USB4 v2 / TB5", bitsPerSecond: Int64(lanes) * gbps * 1_000_000_000,
                 lanes: lanes, isAsymmetric: asymmetric)
    }

    @Test func bandwidthBoostIsNotADowngrade() {
        let symmetric = Self.tb(lanes: 2, gbps: 40)
        let boosted = Self.tb(lanes: 3, gbps: 40, asymmetric: true)
        #expect(linkDiff(symmetric, boosted).allSatisfy { !$0.isDowngrade })
        #expect(linkDiff(boosted, symmetric).allSatisfy { !$0.isDowngrade })
        #expect(linkDiff(boosted, symmetric).isEmpty)
        #expect(linkDiff(symmetric, boosted).isEmpty)
    }

    @Test func realThunderboltDowngradesAreStillReported() throws {
        let down = try #require(linkDiff(Self.tb(lanes: 2, gbps: 40), Self.tb(lanes: 1, gbps: 40)).first)
        #expect(down.kind == .linkChanged)
        #expect(down.isDowngrade)
        // Bandwidth Boost at a lower lane rate is slower.
        #expect(linkDiff(Self.tb(lanes: 3, gbps: 40, asymmetric: true), Self.tb(lanes: 3, gbps: 20, asymmetric: true))
            .first?.isDowngrade == true)
        // Leaving Bandwidth Boost for a single lane is slower too.
        #expect(linkDiff(Self.tb(lanes: 3, gbps: 40, asymmetric: true), Self.tb(lanes: 1, gbps: 40))
            .first?.isDowngrade == true)
        // A faster lane rate with Bandwidth Boost is an upgrade.
        let up = try #require(linkDiff(Self.tb(lanes: 2, gbps: 20), Self.tb(lanes: 3, gbps: 40, asymmetric: true)).first)
        #expect(!up.isDowngrade)
        #expect(up.title == "Dock sped up")
    }

    @Test func displayPortFallbackIsStillADowngrade() {
        func dp(_ gbps: Int64, lanes: Int) -> LinkInfo {
            LinkInfo(family: .displayPort, generation: "DisplayPort", bitsPerSecond: gbps * 1_000_000_000, lanes: lanes)
        }
        #expect(SnapshotDiffer.linkChange(from: dp(32, lanes: 4), to: dp(16, lanes: 2)) == .slower)
        #expect(SnapshotDiffer.linkChange(from: dp(16, lanes: 2), to: dp(32, lanes: 4)) == .faster)
        #expect(SnapshotDiffer.linkChange(from: dp(32, lanes: 4), to: dp(32, lanes: 4)) == nil)
    }

    // MARK: Diagnostics

    @Test func diagnosticEventsCarryTheirSeverity() {
        let hold = Diagnostic(id: "notCharging:battery", kind: .notCharging, severity: .info, title: "Charging on hold",
                              detail: "Nothing is wrong.")
        let slow = Diagnostic(id: "slowCharger:charger", kind: .slowCharger, severity: .warning, title: "Slow charger",
                              detail: "…")
        let events = diff(F.snapshot(), F.snapshot(diagnostics: [hold, slow]))
        #expect(events.map(\.kind) == [.diagnosticRaised, .diagnosticRaised])
        #expect(events.map(\.severity) == [.info, .warning])
        #expect(events.map(\.subjectID) == ["notCharging:battery", "slowCharger:charger"])
        // Other kinds carry no severity.
        let t9 = F.usbDevice("usb:t9", "Samsung T9", bps: 10_000_000_000)
        let connected = diff(F.snapshot(ports: [F.usbC(2, "Left Front")]),
                             F.snapshot(ports: [F.usbC(2, "Left Front", devices: [t9])]))
        #expect(connected.first?.severity == nil)
        #expect(connected.first?.subjectID == "usb:t9")
    }

    @Test func eventsWithoutNewFieldsStillDecode() throws {
        let json = """
        {"id":"deviceConnected:usb:t9:1","date":0,"kind":"deviceConnected","title":"T9 connected",
         "detail":"","isDowngrade":false}
        """
        let event = try JSONDecoder().decode(ConnectionEvent.self, from: Data(json.utf8))
        #expect(event.severity == nil)
        #expect(event.subjectID == nil)
    }

    // MARK: Names

    @Test func controlSequencesNeverReachTitles() throws {
        let evil = F.usbDevice("usb:evil", "Evil\u{1B}[2J\u{07}Drive\u{9B}31m\r\nX", bps: 480_000_000)
        let display = DisplayInfo(id: "display:1:2:cg3", name: "Panel\u{1B}]52;c;aGk=\u{07}", isBuiltin: false)
        let events = diff(F.snapshot(ports: [F.usbC(1, "Left Center")]),
                          F.snapshot(ports: [F.usbC(1, "Left Center", devices: [evil])], displays: [display]))
        #expect(events.count == 2)
        for event in events {
            let scalars = (event.title + event.detail).unicodeScalars
            #expect(!scalars.contains { $0.properties.generalCategory == .control }, "\(event.title)")
        }
        #expect(events.first?.title == "Evil [2J Drive 31m X connected")
        #expect(events.last?.title == "Panel ]52;c;aGk= connected")
    }
}
