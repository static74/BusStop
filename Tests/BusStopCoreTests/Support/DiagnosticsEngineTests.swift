import Foundation
import Testing
@testable import BusStopCore

@Suite("Diagnostics")
struct DiagnosticsEngineTests {
    typealias F = SupportFixtures

    private func evaluate(_ snapshot: HostSnapshot, raw: RawSnapshot? = nil,
                          baseline: [String: Int] = [:]) -> [Diagnostic] {
        DiagnosticsEngine.evaluate(snapshot, raw: raw, baseline: baseline)
    }

    private func kinds(_ diagnostics: [Diagnostic]) -> [DiagnosticKind] {
        diagnostics.map(\.kind)
    }

    // MARK: Baseline

    @Test func quietForAHealthySetup() {
        let t9 = F.usbDevice("usb:t9", "Samsung T9", bps: 10_000_000_000, milliwatts: 4_500)
        let snapshot = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [t9]), F.usbC(2, "Left Front")])
        #expect(evaluate(snapshot).isEmpty)
    }

    // MARK: USB 2 fallback

    @Test func usb2FallbackOnAUSB3Port() throws {
        let drive = F.usbDevice("usb:t9", "Samsung T9", bps: 480_000_000, milliwatts: 500, usbVersion: "3.2")
        let snapshot = F.snapshot(ports: [F.usbC(2, "Left Front", devices: [drive])])
        let finding = try #require(evaluate(snapshot).first)
        #expect(finding.kind == .usb2Fallback)
        #expect(finding.severity == .warning)
        #expect(finding.id == "usb2Fallback:usb:t9")
        #expect(finding.title == "Samsung T9 is running at USB 2 speed")
        #expect(finding.detail.contains("Left Front · USB-C"))
        #expect(finding.detail.contains("480 Mb/s"))
        #expect(finding.detail.contains("5 Gb/s"))
        #expect(finding.suggestion?.contains("cable") == true)
        #expect(finding.portKey == PortKey(type: 2, number: 2))
        #expect(finding.deviceID == "usb:t9")
    }

    @Test func usb2FallbackUsesRawBCDWhenVersionIsMissing() {
        let drive = F.usbDevice("usb:x", "Drive", bps: 480_000_000, usbVersion: nil, properties: ["bcdUSB": 0x0310])
        let snapshot = F.snapshot(ports: [F.usbC(1, "Left Center", supported: [.usb2, .usb3], devices: [drive])])
        #expect(kinds(evaluate(snapshot)) == [.usb2Fallback])
    }

    @Test func usb2FallbackNegatives() {
        let fast = F.usbDevice("usb:a", "Fast", bps: 10_000_000_000, usbVersion: "3.2")
        let usb2 = F.usbDevice("usb:b", "Mouse", kind: .mouse, bps: 12_000_000, usbVersion: "2.0")
        let unknownRate = F.usbDevice("usb:c", "Unknown", bps: nil, usbVersion: "3.0")
        let onUSB2Port = F.usbDevice("usb:d", "Drive", bps: 480_000_000, usbVersion: "3.0")
        let snapshot = F.snapshot(ports: [
            F.usbC(1, "Left Center", devices: [fast, usb2, unknownRate]),
            F.usbC(2, "Left Front", supported: [.usb2], devices: [onUSB2Port]),
        ], otherDevices: [F.usbDevice("usb:e", "Loose", bps: 480_000_000, usbVersion: "3.0")])
        #expect(evaluate(snapshot).isEmpty)
    }

    @Test func usb2FallbackReportsOnlyTheTopDevice() {
        let drive = F.usbDevice("usb:drive", "Drive", bps: 480_000_000, usbVersion: "3.2")
        let hub = F.hub("usb:hub", "USB 3 hub", bps: 480_000_000, selfPowered: true, children: [drive])
        let snapshot = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [hub])])
        let findings = evaluate(snapshot)
        #expect(findings.map(\.id) == ["usb2Fallback:usb:hub"])
    }

    @Test func usb2FallbackBehindAUSB2Hub() throws {
        let drive = F.usbDevice("usb:drive", "Drive", bps: 480_000_000, usbVersion: "3.2")
        let hub = F.usbDevice("usb:hub", "Old hub", kind: .hub, bps: 480_000_000, usbVersion: "2.0", selfPowered: true,
                              children: [drive])
        let snapshot = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [hub])])
        let finding = try #require(evaluate(snapshot).first)
        #expect(finding.id == "usb2Fallback:usb:drive")
        #expect(finding.detail.contains("Old hub"))
        #expect(finding.suggestion?.contains("USB 3 hub") == true)
    }

    // MARK: Thunderbolt bottleneck

    private func thunderboltRaw(current: Int64, hostMask: Int64, deviceMask: Int64,
                                linkAncestry: Bool = true) -> RawSnapshot {
        let hostLane = RawNode(id: 101, className: "IOThunderboltPort", name: "IOThunderboltPort", location: "1",
                               properties: ["Port Number": 1, "Socket ID": "1", "Description": "Thunderbolt Port",
                                            "Current Link Speed": .int(current), "Supported Link Speed": .int(hostMask),
                                            "Current Link Width": 2])
        let host = RawThunderboltSwitch(
            node: RawNode(id: 100, className: "IOThunderboltSwitchType5", name: "IOThunderboltSwitchType5",
                          properties: ["Depth": 0, "UID": 1, "Upstream Port Number": 5]),
            ports: [hostLane])
        let deviceLane = RawNode(id: 201, className: "IOThunderboltPort", name: "IOThunderboltPort", location: "1",
                                 properties: ["Port Number": 1, "Description": "Thunderbolt Port",
                                              "Current Link Speed": .int(current),
                                              "Supported Link Speed": .int(deviceMask)])
        let device = RawThunderboltSwitch(
            node: RawNode(id: 200, className: "IOThunderboltSwitchIntelJHL8440", name: "IOThunderboltSwitch",
                          properties: ["Depth": 1, "UID": 0xa1b2c3d4, "Upstream Port Number": 1,
                                       "Device Vendor Name": "CalDigit", "Device Model Name": "TS4"]),
            parentSwitchID: 100,
            ports: [deviceLane],
            ancestry: linkAncestry ? [RawAncestor(id: 101, className: "IOThunderboltPort", name: "IOThunderboltPort")] : [])
        return RawSnapshot(capturedAt: F.date, machine: MachineInfo(model: "Mac17,9", osVersion: "27.0", hasBattery: true),
                           thunderboltSwitches: [host, device])
    }

    private func dockSnapshot() -> HostSnapshot {
        let dock = DeviceNode(id: "tb:a1b2c3d4", registryID: 200, bus: .thunderbolt, kind: .dock, name: "CalDigit TS4",
                              link: F.thunderboltLink(20), chainDepth: 1)
        return F.snapshot(ports: [F.usbC(1, "Left Center", devices: [dock])])
    }

    @Test func thunderboltBottleneckWhenBothEndsAreFaster() throws {
        let raw = thunderboltRaw(current: 0x8, hostMask: 0xE, deviceMask: 0xC)
        let finding = try #require(evaluate(dockSnapshot(), raw: raw).first)
        #expect(finding.kind == .thunderboltBottleneck)
        #expect(finding.severity == .info)
        #expect(finding.id == "thunderboltBottleneck:tb:a1b2c3d4")
        #expect(finding.deviceID == "tb:a1b2c3d4")
        #expect(finding.portKey == PortKey(type: 2, number: 1))
        #expect(finding.detail.contains("10 Gb/s per lane"))
        #expect(finding.detail.contains("20 Gb/s per lane"))
        #expect(finding.suggestion?.contains("40 Gb/s") == true)
    }

    @Test func thunderboltBottleneckFindsTheDeviceByUIDAndWithoutAncestry() throws {
        let raw = thunderboltRaw(current: 0x4, hostMask: 0xE, deviceMask: 0xE, linkAncestry: false)
        let dock = DeviceNode(id: "tb:0xA1B2C3D4", bus: .thunderbolt, kind: .dock, name: "Dock")
        let snapshot = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [dock])])
        let finding = try #require(evaluate(snapshot, raw: raw).first)
        #expect(finding.deviceID == "tb:0xA1B2C3D4")
        #expect(finding.suggestion?.contains("80 Gb/s") == true)
    }

    @Test func thunderboltBottleneckNegatives() {
        // Already at the fastest common speed.
        #expect(evaluate(dockSnapshot(), raw: thunderboltRaw(current: 0x4, hostMask: 0xE, deviceMask: 0xC)).isEmpty)
        // The device itself cannot go faster.
        #expect(evaluate(dockSnapshot(), raw: thunderboltRaw(current: 0x8, hostMask: 0xE, deviceMask: 0x8)).isEmpty)
        // Idle link.
        #expect(evaluate(dockSnapshot(), raw: thunderboltRaw(current: 0, hostMask: 0xE, deviceMask: 0xE)).isEmpty)
        // Unknown masks.
        #expect(evaluate(dockSnapshot(), raw: thunderboltRaw(current: 0x8, hostMask: 0, deviceMask: 0xC)).isEmpty)
        // No raw capture.
        #expect(evaluate(dockSnapshot()).isEmpty)
    }

    @Test func thunderboltSpeedCodes() {
        #expect(DiagnosticsEngine.perLaneGbps(code: 0x8) == 10)
        #expect(DiagnosticsEngine.perLaneGbps(code: 0x4) == 20)
        #expect(DiagnosticsEngine.perLaneGbps(code: 0x2) == 40)
        #expect(DiagnosticsEngine.perLaneGbps(code: 0x1) == nil)
        #expect(DiagnosticsEngine.fastestPerLaneGbps(mask: 0xC) == 20)
        #expect(DiagnosticsEngine.fastestPerLaneGbps(mask: 0xE) == 40)
        #expect(DiagnosticsEngine.fastestPerLaneGbps(mask: 0x1) == nil)
    }

    // MARK: Charger

    private func chargerSnapshot(watts: Int = 20, laptop: Bool = true, charging: Bool = false, full: Bool = false,
                                 connected: Bool = true, reason: Int? = nil) -> HostSnapshot {
        let charger = F.charger(name: "\(watts)W USB-C Power Adapter", watts: watts,
                                port: PortKey(type: 2, number: 1))
        let battery = laptop
            ? BatteryInfo(percent: 50, isCharging: charging, isFullyCharged: full, externalConnected: connected,
                          notChargingReason: reason)
            : nil
        return F.snapshot(machine: laptop ? F.laptop() : F.desktop(),
                          ports: [F.usbC(1, "Left Center", connected: true)],
                          power: PowerSummary(charger: charger, battery: battery, hasBattery: laptop))
    }

    @Test func slowCharger() throws {
        let finding = try #require(evaluate(chargerSnapshot()).first)
        #expect(finding.kind == .slowCharger)
        #expect(finding.severity == .warning)
        #expect(finding.id == "slowCharger:charger")
        #expect(finding.title.contains("20 W"))
        #expect(finding.detail.contains("Left Center · USB-C"))
        #expect(finding.suggestion?.contains("30 W") == true)
    }

    @Test func slowChargerNegatives() {
        #expect(evaluate(chargerSnapshot(watts: 30)).isEmpty)
        #expect(evaluate(chargerSnapshot(charging: true)).isEmpty)
        #expect(evaluate(chargerSnapshot(full: true)).isEmpty)
        #expect(evaluate(chargerSnapshot(connected: false)).isEmpty)
        #expect(evaluate(chargerSnapshot(laptop: false)).isEmpty)
        // A battery-health hold explains the pause; the charger is not to blame.
        #expect(!kinds(evaluate(chargerSnapshot(reason: 1 << 24))).contains(.slowCharger))
    }

    @Test func notCharging() throws {
        let findings = evaluate(chargerSnapshot(watts: 96, reason: 128))
        let finding = try #require(findings.first)
        #expect(findings.count == 1)
        #expect(finding.kind == .notCharging)
        #expect(finding.severity == .info)
        #expect(finding.id == "notCharging:battery")
        #expect(finding.detail.contains("0x80"))
    }

    @Test func notChargingExplainsBatteryHealthHold() throws {
        let finding = try #require(evaluate(chargerSnapshot(watts: 96, reason: 1 << 24)).first)
        #expect(finding.kind == .notCharging)
        #expect(finding.title.contains("protect the battery"))
    }

    @Test func notChargingNegatives() {
        #expect(evaluate(chargerSnapshot(watts: 96, reason: 0)).isEmpty)
        #expect(evaluate(chargerSnapshot(watts: 96, full: true, reason: 4_194_305)).isEmpty)
        #expect(evaluate(chargerSnapshot(watts: 96, connected: false, reason: 128)).isEmpty)
        #expect(evaluate(chargerSnapshot(watts: 96, charging: true, reason: 128)).isEmpty)
    }

    @Test func notChargingFromRawBatteryKeys() {
        var raw = RawSnapshot(capturedAt: F.date, machine: MachineInfo(model: "Mac17,9", osVersion: "27.0",
                                                                         hasBattery: true))
        raw.battery = ["ExternalConnected": true, "IsCharging": false, "FullyCharged": false,
                       "ChargerData": ["NotChargingReason": 2]]
        let snapshot = F.snapshot(ports: [F.usbC(1, "Left Center")], power: PowerSummary(hasBattery: true))
        #expect(kinds(evaluate(snapshot, raw: raw)) == [.notCharging])

        raw.battery = ["ExternalConnected": "Yes", "IsCharging": "No", "NotChargingReason": "8"]
        #expect(kinds(evaluate(snapshot, raw: raw)) == [.notCharging])

        raw.battery = ["ExternalConnected": [1, 2], "NotChargingReason": "lots"]
        #expect(evaluate(snapshot, raw: raw).isEmpty)
    }

    // MARK: Hub budget

    private func hubSnapshot(_ hub: DeviceNode) -> HostSnapshot {
        F.snapshot(ports: [F.usbC(1, "Left Center", devices: [hub])])
    }

    @Test func busPoweredHubOverBudget() throws {
        let hub = F.hub("usb:hub", children: [
            F.usbDevice("usb:a", "Drive A", bps: 5_000_000_000, milliwatts: 2_500),
            F.usbDevice("usb:b", "Drive B", bps: 5_000_000_000, milliwatts: 2_500),
        ])
        let finding = try #require(evaluate(hubSnapshot(hub)).first)
        #expect(finding.kind == .hubOverBudget)
        #expect(finding.severity == .warning)
        #expect(finding.id == "hubOverBudget:usb:hub")
        #expect(finding.detail.contains("5 W"))
        #expect(finding.detail.contains("4.5 W"))
        #expect(finding.detail.contains("2 devices"))
    }

    @Test func usb2HubHasASmallerBudget() {
        let hub = F.usbDevice("usb:hub", "USB 2 hub", kind: .hub, bps: 480_000_000, usbVersion: "2.0",
                              selfPowered: false, children: [
            F.usbDevice("usb:a", "Mouse", kind: .mouse, bps: 12_000_000, milliwatts: 1_500, usbVersion: "2.0"),
            F.usbDevice("usb:b", "Keyboard", kind: .keyboard, bps: 12_000_000, milliwatts: 1_500, usbVersion: "2.0"),
        ])
        #expect(kinds(evaluate(hubSnapshot(hub))) == [.hubOverBudget])
    }

    @Test func hubBudgetNegatives() {
        let children = [
            F.usbDevice("usb:a", "Drive A", bps: 5_000_000_000, milliwatts: 4_000),
            F.usbDevice("usb:b", "Drive B", bps: 5_000_000_000, milliwatts: 4_000),
        ]
        #expect(evaluate(hubSnapshot(F.hub("usb:hub", selfPowered: true, children: children))).isEmpty)
        #expect(evaluate(hubSnapshot(F.hub("usb:hub", selfPowered: nil, children: children))).isEmpty)
        let light = [F.usbDevice("usb:a", "Drive A", bps: 5_000_000_000, milliwatts: 4_500)]
        #expect(evaluate(hubSnapshot(F.hub("usb:hub", children: light))).isEmpty)
    }

    @Test func hubPowerKeysDecideWhenTheModelDoesNot() {
        let children = [F.usbDevice("usb:a", "Drive", bps: 5_000_000_000, milliwatts: 4_800)]
        var hub = F.hub("usb:hub", selfPowered: nil, children: children)
        hub.properties = ["kUSBHubPowerSupply": 0]
        #expect(kinds(evaluate(hubSnapshot(hub))) == [.hubOverBudget])
        hub.properties = ["kUSBHubPowerSupplyType": 1, "kUSBHubPowerSupply": 0]
        #expect(evaluate(hubSnapshot(hub)).isEmpty)
    }

    @Test func selfPoweredSubHubDoesNotCountAgainstItsParent() {
        let inner = F.hub("usb:inner", selfPowered: true, children: [
            F.usbDevice("usb:a", "Drive", bps: 5_000_000_000, milliwatts: 4_500),
            F.usbDevice("usb:b", "Drive", bps: 5_000_000_000, milliwatts: 4_500),
        ])
        let outer = F.hub("usb:outer", children: [inner])
        #expect(evaluate(hubSnapshot(outer)).isEmpty)
    }

    // MARK: Deep chain

    private func chain(depth: Int) -> DeviceNode {
        var node = DeviceNode(id: "tb:\(depth)", bus: .thunderbolt, kind: .thunderboltDevice, name: "Drive \(depth)",
                              chainDepth: depth)
        for level in stride(from: depth - 1, through: 1, by: -1) {
            node = DeviceNode(id: "tb:\(level)", bus: .thunderbolt, kind: .thunderboltDevice, name: "Drive \(level)",
                              chainDepth: level, children: [node])
        }
        return node
    }

    @Test func deepChain() throws {
        let snapshot = F.snapshot(ports: [F.usbC(1, "Left Center", devices: [chain(depth: 6)])])
        let finding = try #require(evaluate(snapshot).first)
        #expect(finding.kind == .deepChain)
        #expect(finding.severity == .info)
        #expect(finding.id == "deepChain:tb:6")
        #expect(finding.title.contains("6"))
        #expect(finding.portKey == PortKey(type: 2, number: 1))
        #expect(evaluate(F.snapshot(ports: [F.usbC(1, "Left Center", devices: [chain(depth: 5)])])).isEmpty)
    }

    @Test func deepChainFromRawDepths() {
        var switches: [RawThunderboltSwitch] = []
        for depth in 0...6 {
            var properties = PropertyBag()
            properties["Depth"] = .int(Int64(depth))
            properties["UID"] = .int(Int64(900 + depth))
            let node = RawNode(id: UInt64(300 + depth), className: "IOThunderboltSwitch", name: "IOThunderboltSwitch",
                               properties: properties)
            let parent: UInt64? = depth == 0 ? nil : UInt64(299 + depth)
            switches.append(RawThunderboltSwitch(node: node, parentSwitchID: parent))
        }
        let raw = RawSnapshot(capturedAt: F.date, machine: MachineInfo(model: "Mac17,9", osVersion: "27.0",
                                                                         hasBattery: true),
                              thunderboltSwitches: switches)
        let snapshot = F.snapshot(ports: [F.usbC(1, "Left Center")])
        #expect(evaluate(snapshot, raw: raw).map(\.id) == ["deepChain:tb:\(String(906, radix: 16))"])
    }

    // MARK: Liquid and overcurrent

    @Test func liquidDetected() throws {
        let wet = F.usbC(2, "Left Front", liquid: true)
        let finding = try #require(evaluate(F.snapshot(ports: [wet])).first)
        #expect(finding.kind == .liquidDetected)
        #expect(finding.severity == .critical)
        #expect(finding.id == "liquidDetected:2/2")
        #expect(finding.title == "Liquid detected in Left Front · USB-C")

        let fromKeys = F.usbC(1, "Left Center", properties: ["LDCM_LiquidDetected": "Yes"])
        #expect(kinds(evaluate(F.snapshot(ports: [fromKeys]))) == [.liquidDetected])

        let dry = F.usbC(1, "Left Center", properties: ["LDCM_LiquidDetected": false])
        #expect(evaluate(F.snapshot(ports: [dry])).isEmpty)
    }

    @Test func overcurrentSinceLaunch() throws {
        let port = F.usbC(1, "Left Center", statistics: PortStatistics(overcurrentCount: 3))
        let finding = try #require(evaluate(F.snapshot(ports: [port]), baseline: ["2/1": 1]).first)
        #expect(finding.kind == .overcurrent)
        #expect(finding.severity == .warning)
        #expect(finding.id == "overcurrent:2/1")
        #expect(finding.detail.contains("2 times"))

        #expect(evaluate(F.snapshot(ports: [port]), baseline: ["2/1": 3]).isEmpty)
        #expect(evaluate(F.snapshot(ports: [port])).isEmpty)

        let fromKeys = F.usbC(1, "Left Center", properties: ["Overcurrent Count": 1])
        #expect(kinds(evaluate(F.snapshot(ports: [fromKeys]), baseline: ["2/1": 0])) == [.overcurrent])
    }

    // MARK: Reduced detail

    @Test func reducedDetail() {
        var intel = F.laptop()
        intel.isAppleSilicon = false
        let onIntel = evaluate(F.snapshot(machine: intel, ports: [F.usbC(1, "Left Center")]))
        #expect(onIntel.map(\.id) == ["reducedDetail:machine"])
        #expect(onIntel.first?.severity == .info)

        #expect(kinds(evaluate(F.snapshot(ports: []))) == [.reducedDetail])

        let noted = F.snapshot(ports: [F.usbC(1, "Left Center")], captureNotes: ["Port details unavailable: IOPort plane missing"])
        #expect(kinds(evaluate(noted)) == [.reducedDetail])

        let unrelated = F.snapshot(ports: [F.usbC(1, "Left Center")], captureNotes: ["SMC unavailable"])
        #expect(evaluate(unrelated).isEmpty)
    }

    // MARK: Ordering

    @Test func sortedBySeverityThenID() {
        let wet = F.usbC(3, "Right Center", liquid: true)
        let slow = F.usbC(2, "Left Front", devices: [F.usbDevice("usb:z", "Drive", bps: 480_000_000)])
        let fallback = F.usbC(1, "Left Center", devices: [F.usbDevice("usb:a", "Stick", bps: 480_000_000)])
        let snapshot = F.snapshot(ports: [slow, fallback, wet, F.usbC(4, "Right Rear", statistics:
            PortStatistics(overcurrentCount: 2))], displays: [])
        let ids = evaluate(snapshot, baseline: ["2/4": 0]).map(\.id)
        #expect(ids == ["liquidDetected:2/3", "overcurrent:2/4", "usb2Fallback:usb:a", "usb2Fallback:usb:z"])
    }
}
