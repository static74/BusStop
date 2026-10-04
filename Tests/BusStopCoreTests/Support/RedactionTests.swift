import Foundation
import Testing
@testable import BusStopCore

/// Per-unit identifiers (Thunderbolt UIDs, HPM and SMC UUIDs, USB container
/// IDs, DisplayID serials) in redacted exports, and redaction of single
/// events for `busstop --watch`.
@Suite("Exporter: unit identifiers")
struct RedactionTests {
    typealias S = DemoTestSupport

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// Every unit identifier in a raw capture, in the forms an export could
    /// print it: UIDs as decimal JSON numbers and as hex (padded and not),
    /// UUIDs as captured and normalized.
    static func identifiers(in raw: RawSnapshot) -> Set<String> {
        var result = Set<String>()
        func collect(_ values: [String: PlistValue]) {
            for (key, value) in values {
                if key.lowercased() == "uid", let number = value.int64Value {
                    result.insert(String(number))
                    result.insert(String(UInt64(bitPattern: number), radix: 16))
                    result.insert(TopologyText.hex(UInt64(bitPattern: number), width: 16))
                } else if Exporter.isUnitIdentifierKey(key), let string = value.stringValue,
                          let normalized = PowerParser.normalizedUUID(string) {
                    result.insert(string.lowercased())
                    result.insert(normalized)
                }
                switch value {
                case .dict(let inner): collect(inner)
                case .array(let items): items.forEach { if case .dict(let inner) = $0 { collect(inner) } }
                default: break
                }
            }
        }
        raw.portNodes.forEach { collect($0.properties.values) }
        raw.usbDevices.forEach { collect($0.node.properties.values) }
        raw.thunderboltSwitches.forEach { sw in
            collect(sw.node.properties.values)
            sw.ports.forEach { collect($0.properties.values) }
        }
        if let battery = raw.battery { collect(battery.values) }
        if let adapter = raw.adapter { collect(adapter.values) }
        for uuid in raw.portControllerUUIDs.values {
            result.insert(uuid.lowercased())
            if let normalized = PowerParser.normalizedUUID(uuid) { result.insert(normalized) }
        }
        for channel in raw.smcChannels {
            if let normalized = PowerParser.normalizedUUID(channel.uuid) { result.insert(normalized) }
        }
        return result
    }

    @Test(arguments: DemoScenario.allCases)
    func noUnitIdentifierSurvivesRedaction(_ scenario: DemoScenario) throws {
        let raw = scenario.raw(at: S.date)
        let identifiers = Self.identifiers(in: raw)
        #expect(!identifiers.isEmpty)
        let rawOutput = text(try Exporter.rawJSON(raw, redact: true)).lowercased()
        let snapshotOutput = text(try Exporter.json(S.snapshot(scenario), redact: true)).lowercased()
        let leakedRaw = identifiers.filter { rawOutput.contains($0) }
        let leakedSnapshot = identifiers.filter { snapshotOutput.contains($0) }
        #expect(leakedRaw.isEmpty, "raw: \(leakedRaw)")
        #expect(leakedSnapshot.isEmpty, "snapshot: \(leakedSnapshot)")
        // The search is not vacuous: without redaction they are there.
        let plain = text(try Exporter.rawJSON(raw, redact: false)).lowercased()
        #expect(identifiers.contains { plain.contains($0) })
    }

    /// The shape of a snapshot without ids: ports with their power and
    /// device trees by name and kind, and where each display went.
    private struct Shape: Equatable {
        struct Tree: Equatable {
            var name: String
            var kind: DeviceKind
            var children: [Tree]
        }

        var ports: [String]
        var power: [PortPower?]
        var trees: [[Tree]]
        var other: [Tree]
        var displays: [String]
        var diagnostics: [DiagnosticKind]
        var charger: PortKey?

        init(_ snapshot: HostSnapshot) {
            func tree(_ node: DeviceNode) -> Tree {
                Tree(name: node.name, kind: node.kind, children: node.children.map(tree))
            }
            ports = snapshot.ports.map { "\($0.key) \($0.label.title) \($0.isConnected)" }
            power = snapshot.ports.map(\.power)
            trees = snapshot.ports.map { $0.devices.map(tree) }
            other = snapshot.otherDevices.map(tree)
            displays = snapshot.displays.map { "\($0.name) \($0.portKey?.description ?? "-")" }
            diagnostics = snapshot.diagnostics.map(\.kind)
            charger = snapshot.power.charger?.portKey
        }
    }

    @Test(arguments: DemoScenario.allCases)
    func redactedCaptureBuildsTheSameTopology(_ scenario: DemoScenario) throws {
        let raw = scenario.raw(at: S.date)
        let redacted = try Exporter.decodeRaw(Exporter.rawJSON(raw, redact: true))
        let original = TopologyBuilder.build(raw)
        let rebuilt = TopologyBuilder.build(redacted)
        #expect(Shape(rebuilt) == Shape(original))
        // The SMC join still finds every port's live reading.
        #expect(rebuilt.ports.map(\.power?.source) == original.ports.map(\.power?.source))
        // Thunderbolt ids keep their shape and vendor, with a stand-in serial.
        let ids = rebuilt.allDevices.map(\.device.id).filter { $0.hasPrefix("tb:") }
        #expect(ids.count == original.allDevices.filter { $0.device.id.hasPrefix("tb:") }.count)
        #expect(ids.allSatisfy { !$0.hasPrefix("tb:reg-") && $0.count == 19 })
    }

    @Test func dockStationExportHidesTheDockUID() throws {
        let uid = DemoDockStation.dockUID
        let hex = TopologyText.hex(UInt64(bitPattern: uid), width: 16)
        let snapshot = S.snapshot(.dockStation)
        #expect(snapshot.allDevices.contains { $0.device.id == "tb:\(hex)" })

        let output = text(try Exporter.json(snapshot, redact: true))
        #expect(!output.contains(hex))
        #expect(!output.contains(String(uid)))
        let redacted = Exporter.redacted(snapshot)
        let dock = try #require(redacted.allDevices.first { $0.device.bus == .thunderbolt }?.device)
        // The vendor half survives; the unit half is a running number.
        #expect(dock.id == "tb:003d000000000001")
        #expect(dock.properties?["UID"] == .int(0x003D_0000_0000_0001))

        let raw = try Exporter.decodeRaw(Exporter.rawJSON(DemoScenario.dockStation.raw(at: S.date)))
        let uids = raw.thunderboltSwitches.compactMap { $0.node.properties.int64("UID") }
        #expect(!uids.contains(uid))
        #expect(Set(uids).count == raw.thunderboltSwitches.count)
        #expect(uids.allSatisfy { $0 & 0xFFFF_FFFF_FFFF < 16 })
    }

    @Test func diagnosticIdsUseTheSameStandIns() {
        let device = DeviceNode(id: "tb:05ac2b448d100f01", bus: .thunderbolt, kind: .display, name: "Studio Display",
                                properties: ["UID": .int(0x05AC_2B44_8D10_0F01)])
        let snapshot = SupportFixtures.snapshot(
            ports: [SupportFixtures.usbC(1, "Left Center", devices: [device])],
            displays: [DisplayInfo(id: "display:610:ae3a:742455795", name: "Studio Display", serialNumber: 742_455_795,
                                   isBuiltin: false, portKey: PortKey(type: 2, number: 1),
                                   representingDeviceID: "tb:05ac2b448d100f01")],
            diagnostics: [
                Diagnostic(id: "thunderboltBottleneck:tb:5ac2b448d100f01", kind: .thunderboltBottleneck,
                           severity: .info, title: "Slow", detail: "", deviceID: "tb:05ac2b448d100f01"),
                Diagnostic(id: "deepChain:tb:abcdef", kind: .deepChain, severity: .info, title: "Deep", detail: ""),
            ])
        let redacted = Exporter.redacted(snapshot)
        #expect(redacted.ports[0].devices[0].id == "tb:05ac000000000001")
        #expect(redacted.ports[0].devices[0].properties?["UID"] == .int(0x05AC_0000_0000_0001))
        #expect(redacted.displays[0].id == "display:610:ae3a:REDACTED")
        #expect(redacted.displays[0].representingDeviceID == "tb:05ac000000000001")
        #expect(redacted.diagnostics[0].id == "thunderboltBottleneck:tb:5ac000000000001")
        #expect(redacted.diagnostics[0].deviceID == "tb:05ac000000000001")
        #expect(redacted.diagnostics[1].id == "deepChain:tb:2")
    }

    // MARK: Property bags

    @Test func identifierPropertiesGetStandIns() {
        let bag: PropertyBag = [
            "UID": .int(0x05AC_11E6_A043_2941),
            "kUSBContainerID": "6A1F0E43-9B2C-4D8A-8E2F-1C3B5D7E9F00",
            "PowerSourceOptions": [["UUID": "0B4F1A3C-77D2-4E19-9F0A-2C6E8B1D5A47", "Max Power (mW)": 60_000]],
            "EDID UUID": "1E6D5B71-0000-0000-0000-000000000000",
            "ContainerID": .data(Data(repeating: 0xAB, count: 16)),
            "ConnectionUUID": "C0FFEE",
            "UsbCPortNumber": 2,
        ]
        let redacted = Exporter.redacted(bag)
        #expect(redacted["UID"] == .int(0x05AC_0000_0000_0001))
        #expect(redacted["UsbCPortNumber"] == 2)
        #expect(redacted["ConnectionUUID"] == "REDACTED")
        let container = redacted.string("kUSBContainerID")
        #expect(container?.count == 36)
        #expect(container?.split(separator: "-").map(\.count) == [8, 4, 4, 4, 12])
        #expect(container != bag.string("kUSBContainerID"))
        let option = redacted.bags("PowerSourceOptions")?.first
        #expect(option?.int("Max Power (mW)") == 60_000)
        #expect(option?.string("UUID")?.hasPrefix("00000000-0000-0000-0000-00000000000") == true)
        #expect(redacted.data("ContainerID")?.count == 16)
        #expect(redacted.data("ContainerID")?.contains(0xAB) == false)
        #expect(Exporter.isUnitIdentifierKey("EDID UUID"))
        #expect(!Exporter.isUnitIdentifierKey("UsbCPortNumber"))
        #expect(!Exporter.isUnitIdentifierKey("UIDCount"))
    }

    @Test func dashedAndUndashedUUIDsKeepMatching() throws {
        let dashed = "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D"
        let raw = TopologyFixtures.raw(
            ports: [TopologyFixtures.port(id: 10, number: 1, connected: true)],
            uuids: ["2/1": dashed, "2/2": "1111"],
            smc: [SMCChannel(index: 1, uuid: "9a8b7c6d5e4f4a3b8c2d1e0f9a8b7c6d", volts: 5, amps: 1),
                  SMCChannel(index: 2, uuid: "ffff", volts: 0, amps: 0)])
        let redacted = Exporter.redacted(raw)
        let port = try #require(redacted.portControllerUUIDs["2/1"])
        #expect(port != dashed)
        #expect(port.split(separator: "-").map(\.count) == [8, 4, 4, 4, 12])
        #expect(PowerParser.normalizedUUID(port) == PowerParser.normalizedUUID(redacted.smcChannels[0].uuid))
        #expect(PowerParser.normalizedUUID(redacted.portControllerUUIDs["2/2"])
            != PowerParser.normalizedUUID(redacted.smcChannels[1].uuid))
        #expect(redacted.smcChannels[0].volts == 5)
        // Deterministic.
        #expect(Exporter.redacted(raw) == redacted)
    }

    // MARK: EDID

    @Test func displayIDExtensionSerialsAreBlanked() throws {
        var bytes = [UInt8](repeating: 0, count: 256)
        bytes[0...7] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        bytes[12...15] = [0x78, 0x56, 0x34, 0x12]
        bytes[126] = 1
        // DisplayID 2.0 section: product identification, tiled topology, ContainerID.
        let productID: [UInt8] = [0x20, 0x00, 12, 0x00, 0x10, 0xFA, 0x3A, 0xAE, 0x11, 0x22, 0x33, 0x44, 10, 34, 0]
        var tiled: [UInt8] = [0x28, 0x00, 22] + [UInt8](repeating: 0x01, count: 18)
        tiled += [0x55, 0x66, 0x77, 0x88]
        let container: [UInt8] = [0x29, 0x00, 16] + [UInt8](repeating: 0xC3, count: 16)
        let blocks = productID + tiled + container
        var ext: [UInt8] = [0x70, 0x20, UInt8(blocks.count), 0x00, 0x00] + blocks
        let sectionSum = ext[1...].reduce(0) { ($0 + Int($1)) & 0xFF }
        ext.append(UInt8((256 - sectionSum) & 0xFF))
        for (offset, byte) in ext.enumerated() { bytes[128 + offset] = byte }
        for block in 0...1 {
            let sum = bytes[(block * 128)..<(block * 128 + 127)].reduce(0) { ($0 + Int($1)) & 0xFF }
            bytes[block * 128 + 127] = UInt8((256 - sum) & 0xFF)
        }

        let redacted = [UInt8](Exporter.redactedEDID(Data(bytes)))
        #expect(redacted.count == 256)
        let ext2 = Array(redacted[128..<256])
        // Serial of the product identification block (payload bytes 5–8).
        #expect(Array(ext2[(5 + 3 + 5)..<(5 + 3 + 9)]) == [0, 0, 0, 0])
        // Manufacturer and product code stay.
        #expect(Array(ext2[(5 + 3)..<(5 + 3 + 5)]) == [0x00, 0x10, 0xFA, 0x3A, 0xAE])
        let tiledStart = 5 + productID.count + 3
        #expect(Array(ext2[(tiledStart + 18)..<(tiledStart + 22)]) == [0, 0, 0, 0])
        #expect(ext2[tiledStart] == 0x01)
        let containerStart = 5 + productID.count + tiled.count + 3
        #expect(Array(ext2[containerStart..<(containerStart + 16)]) == [UInt8](repeating: 0, count: 16))
        // Both checksums still hold.
        let sectionEnd = 5 + blocks.count
        #expect(ext2[1...sectionEnd].reduce(0) { ($0 + Int($1)) & 0xFF } == 0)
        #expect(redacted[0..<128].reduce(0) { ($0 + Int($1)) & 0xFF } == 0)
        #expect(ext2.reduce(0) { ($0 + Int($1)) & 0xFF } == 0)

        // A CTA-861 extension is left as it is.
        var cta = bytes
        cta[128] = 0x02
        let ctaRedacted = [UInt8](Exporter.redactedEDID(Data(cta)))
        #expect(Array(ctaRedacted[128..<256]) == Array(cta[128..<256]))
        // An extension count that runs past the data is ignored.
        var short = Array(bytes[0..<128])
        short[126] = 3
        #expect(Exporter.redactedEDID(Data(short)).count == 128)
    }

    // MARK: Events

    @Test func displayEventsHideThePanelSerial() throws {
        var unplugged = DemoScenario.dockStation.raw(at: S.date)
        unplugged.displays = []
        let with = TopologyBuilder.build(DemoScenario.dockStation.raw(at: S.date))
        let without = TopologyBuilder.build(unplugged)
        let serial = "204588"
        #expect(with.displays.first?.id.hasSuffix(serial) == true)

        for event in SnapshotDiffer.events(from: with, to: without, at: S.date)
            + SnapshotDiffer.events(from: without, to: with, at: S.date) {
            #expect(event.id.contains(serial))
            let redacted = Exporter.redacted(event)
            #expect(redacted.id.contains("display:1e6d:5b71:REDACTED:"))
            #expect(redacted.subjectID == "display:1e6d:5b71:REDACTED")
            let json = text(try JSONEncoder().encode(redacted))
            #expect(!json.contains(serial))
            #expect(redacted.title == event.title)
        }
    }

    @Test func thunderboltEventsHideTheUID() throws {
        let hex = TopologyText.hex(UInt64(bitPattern: DemoDockStation.dockUID), width: 16)
        let event = ConnectionEvent(id: "deviceConnected:tb:\(hex):1790000000000", date: S.date, kind: .deviceConnected,
                                    title: "Dock \(hex) connected", detail: "Rear · \(hex.uppercased())",
                                    deviceID: "tb:\(hex)", subjectID: "tb:\(hex)")
        let redacted = Exporter.redacted(event)
        #expect(redacted.id == "deviceConnected:tb:REDACTED:1790000000000")
        #expect(redacted.deviceID == "tb:REDACTED")
        #expect(redacted.subjectID == "tb:REDACTED")
        #expect(redacted.title == "Dock REDACTED connected")
        #expect(redacted.detail == "Rear · REDACTED")

        // Registry fallbacks, USB ids and short display serials are left alone.
        let plain = ConnectionEvent(id: "deviceConnected:usb:0x01110000:04e8:61fb:1", date: S.date,
                                    kind: .deviceConnected, title: "T9 connected", detail: "",
                                    deviceID: "tb:reg-3e8", subjectID: "display:1:2:1")
        let same = Exporter.redacted(plain)
        #expect(same == plain)
    }

    // MARK: Markdown

    @Test func markdownStripsControlCharacters() {
        let device = SupportFixtures.usbDevice("usb:x", "Evil\u{1B}[2J\r\nName\u{07}", bps: 12_000_000)
        let report = Exporter.markdown(SupportFixtures.snapshot(ports: [SupportFixtures.usbC(1, "Left Center",
                                                                                         devices: [device])]))
        #expect(!report.unicodeScalars.contains { $0 != "\n" && $0.properties.generalCategory == .control })
        #expect(report.contains("**Evil \\[2J Name** (Storage)"))
    }
}
