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

    /// An all-zero container ID identifies nothing and stays as it is, so it
    /// never turns into a stand-in that looks like a real, shared one.
    @Test func zeroContainerIDIsKept() {
        let zero = "00000000-0000-0000-0000-000000000000"
        let bag: PropertyBag = ["kUSBContainerID": .string(zero), "Other UUID": .string(zero)]
        let redacted = Exporter.redacted(bag)
        #expect(redacted.string("kUSBContainerID") == zero)
        #expect(redacted.string("Other UUID") != zero)
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

    @Test func singleIdsForCopyDetails() {
        #expect(Exporter.redactedID("display:1e6d:5b71:204588") == "display:1e6d:5b71:REDACTED")
        #expect(Exporter.redactedID("display:1e6d:5b71:204588#cg2") == "display:1e6d:5b71:REDACTED#cg2")
        #expect(Exporter.redactedID("display:1e6d:5b71:cg2") == "display:1e6d:5b71:cg2")
        #expect(Exporter.redactedID("tb:003d5a1177c20501") == "tb:REDACTED")
        #expect(Exporter.redactedID("tb:reg-3e8") == "tb:reg-3e8")
        #expect(Exporter.redactedID("usb:0x01110000:04e8:61fb") == "usb:0x01110000:04e8:61fb")
    }

    // MARK: Serials in names

    /// A demo capture whose first USB device with a serial also carries it
    /// in its product name, as some devices do.
    private func captureWithSerialInName(_ serial: String) throws -> RawSnapshot {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.usbDevices.firstIndex { $0.node.properties.values["USB Serial Number"] != nil })
        var values = raw.usbDevices[index].node.properties.values
        values["USB Serial Number"] = .string(serial)
        values["kUSBSerialNumberString"] = .string(serial)
        values["USB Product Name"] = .string("Drive \(serial)")
        values["kUSBProductString"] = .string("Drive \(serial)")
        raw.usbDevices[index].node.properties = PropertyBag(values)
        // The registry entry, and an interface, are named after the product too.
        raw.usbDevices[index].node.name = "Drive \(serial)"
        if !raw.usbDevices[index].interfaces.isEmpty { raw.usbDevices[index].interfaces[0].name = "Drive \(serial)" }
        return raw
    }

    @Test func serialsInNamesAreRedactedInEveryFormat() throws {
        let serial = "SNXYZ123"
        let raw = try captureWithSerialInName(serial)
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.allDevices.contains { $0.device.name == "Drive \(serial)" })
        let redactedOutputs = [
            text(try Exporter.rawJSON(raw, redact: true)),
            text(try Exporter.json(snapshot, redact: true)),
            Exporter.markdown(snapshot, redact: true),
            Exporter.textTree(Exporter.redacted(snapshot)),
        ]
        for output in redactedOutputs {
            #expect(!output.contains(serial))
        }
        #expect(text(try Exporter.rawJSON(raw, redact: false)).contains(serial))
        #expect(Exporter.markdown(snapshot, redact: false).contains(serial))
        // The redacted capture still builds the same topology.
        let rebuilt = TopologyBuilder.build(try Exporter.decodeRaw(Exporter.rawJSON(raw, redact: true)))
        #expect(rebuilt.allDevices.count == snapshot.allDevices.count)
    }

    @Test func displaySerialInARawDisplayNameIsRedacted() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.displays.firstIndex { ($0.serialNumber ?? 0) > 999 })
        let serial = String(try #require(raw.displays[index].serialNumber))
        raw.displays[index].name = "Studio Display \(serial)"
        #expect(!text(try Exporter.rawJSON(raw, redact: true)).contains(serial))
        #expect(text(try Exporter.rawJSON(raw, redact: false)).contains(serial))
    }

    @Test func serialsInNamesAreRedactedFromEvents() throws {
        let serial = "SNXYZ123"
        let snapshot = TopologyBuilder.build(try captureWithSerialInName(serial))
        let device = try #require(snapshot.allDevices.first { $0.device.serialNumber == serial }?.device)
        let connected = ConnectionEvent(id: "deviceConnected:\(device.id):1790000000000", date: S.date,
                                        kind: .deviceConnected, title: "\(device.name) connected",
                                        detail: "\(device.name) on Left", deviceID: device.id)
        let redacted = Exporter.redacted(connected, serialsFrom: [snapshot])
        #expect(!redacted.title.contains(serial) && !redacted.detail.contains(serial))
        #expect(Exporter.redacted(connected).title.contains(serial))
    }

    /// A device that has left: its serial is no longer in the snapshot, so it is passed in.
    @Test func serialsOfDevicesNoLongerConnectedAreRedacted() throws {
        let serial = "SNXYZ123"
        let gone = TopologyBuilder.build(try captureWithSerialInName(serial))
        #expect(Exporter.serialsInNames(of: gone).contains(serial))
        let snapshot = S.snapshot(.studioDesk)
        #expect(!Exporter.textSerials(in: snapshot).contains(serial))
        let event = ConnectionEvent(id: "1", date: S.date, kind: .deviceDisconnected,
                                    title: "Drive \(serial) disconnected", detail: "Drive \(serial) on Left")
        let redacted = Exporter.redacted(event, serialsFrom: [snapshot], serials: Exporter.serialsInNames(of: gone))
        #expect(redacted.title == "Drive REDACTED disconnected" && redacted.detail == "Drive REDACTED on Left")
        #expect(Exporter.redacted(event, serialsFrom: [snapshot]).title.contains(serial))

        // A diagnostic still names it (a device that keeps disconnecting), in the snapshot and in exports.
        var withFinding = snapshot
        withFinding.diagnostics.append(Diagnostic(id: "flaky", kind: .flakyConnection, severity: .warning,
                                                  title: "Drive \(serial) keeps disconnecting", detail: ""))
        let serials: Set<String> = [serial]
        #expect(Exporter.redacted(withFinding, serials: serials).diagnostics.last?.title
                == "Drive REDACTED keeps disconnecting")
        #expect(!text(try Exporter.json(withFinding, serials: serials)).contains(serial))
        #expect(!Exporter.markdown(withFinding, serials: serials).contains(serial))
        #expect(Exporter.markdown(withFinding).contains(serial))
    }

    @Test func wholeWordsOnly() {
        #expect(Exporter.redacted("Drive SN-12/34 (SN-12/34)", serials: ["SN-12/34"]) == "Drive REDACTED (REDACTED)")
        #expect(Exporter.redacted("512345 and 1234", serials: ["1234"]) == "512345 and REDACTED")
        #expect(Exporter.redacted("ABC is short", serials: ["ABC"]) == "ABC is short")
    }

    /// A 4-digit device serial in its own name is removed, connected or gone, although a
    /// 4-digit one elsewhere is kept so that "2160" in a resolution stays.
    @Test(arguments: ["1234", "2160"])
    func fourDigitSerialsInTheirOwnNameAreRedacted(_ serial: String) throws {
        let raw = try captureWithSerialInName(serial)
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.allDevices.contains { $0.device.name == "Drive \(serial)" })
        #expect(!text(try Exporter.json(snapshot, redact: true)).contains("Drive \(serial)"))
        #expect(!text(try Exporter.rawJSON(raw, redact: true)).contains("Drive \(serial)"))
        #expect(!Exporter.markdown(snapshot, redact: true).contains("Drive \(serial)"))
        let event = ConnectionEvent(id: "1", date: S.date, kind: .deviceConnected,
                                    title: "Drive \(serial) connected", detail: "")
        #expect(Exporter.redacted(event, serialsFrom: [snapshot]).title == "Drive REDACTED connected")
        let payload = text(try JSONEncoder().encode(WidgetPayload(snapshot: snapshot, events: [event])))
        #expect(!payload.contains("Drive \(serial)"))
        // Unplugged: the serial is kept for the events about it.
        let serials = Exporter.serialsInNames(of: snapshot)
        #expect(serials.contains(serial))
        var gone = event
        gone.title = "Drive \(serial) disconnected"
        let later = WidgetPayload(snapshot: S.snapshot(.studioDesk), events: [gone], serials: serials)
        #expect(later.events.first?.title == "Drive REDACTED disconnected")
    }

    /// Studio desk with the external display named after `serial`, which is its serial number.
    private func displayNamedAfterItsSerial(_ serial: Int) throws -> RawSnapshot {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.displays.firstIndex { $0.name == "Studio Display XDR" })
        raw.displays[index].serialNumber = serial
        raw.displays[index].name = "Studio Display \(serial)"
        return raw
    }

    /// Studio desk with the charger's `key` ("Name" or "Manufacturer") set to `text` and its serial to `serial`.
    private func chargerNamedAfterItsSerial(_ serial: String, key: String = "Name", text: String? = nil) throws
        -> RawSnapshot {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        var battery = try #require(raw.battery).values
        guard case .dict(var details) = battery["AdapterDetails"] else { throw CancellationError() }
        details[key] = .string(text ?? "Charger \(serial)")
        details["SerialString"] = .string(serial)
        battery["AdapterDetails"] = .dict(details)
        raw.battery = PropertyBag(battery)
        var adapter = raw.adapter?.values ?? [:]
        adapter[key] = .string(text ?? "Charger \(serial)")
        adapter["SerialString"] = .string(serial)
        raw.adapter = PropertyBag(adapter)
        return raw
    }

    /// A charger whose manufacturer holds its serial ("Maker 1234") loses it, in the snapshot and the raw capture.
    @Test func chargerManufacturerLosesItsShortSerial() throws {
        let raw = try chargerNamedAfterItsSerial("1234", key: "Manufacturer", text: "Maker 1234")
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.power.charger?.manufacturer == "Maker 1234")
        #expect(!text(try Exporter.json(snapshot, redact: true)).contains("Maker 1234"))
        #expect(!text(try Exporter.rawJSON(raw, redact: true)).contains("Maker 1234"))
    }

    /// An Apple charger names itself on its AppleUVDM node ("User String", "Vendor"), with its serial there too.
    @Test(arguments: [("User String", "Charger"), ("Vendor", "Maker")])
    func chargerSerialOnItsUVDMNodeLeavesTheRawName(_ key: String, _ word: String) throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.portNodes.firstIndex { $0.className == "IOPortTransportProtocolAppleUVDM" })
        var values = raw.portNodes[index].properties.values
        values[key] = .string("\(word) 1234")
        values["Serial Number"] = .string("1234")
        raw.portNodes[index].properties = PropertyBag(values)
        let json = text(try Exporter.rawJSON(raw, redact: true))
        #expect(json.contains("\(word) REDACTED") && !json.contains("\(word) 1234"))
    }

    /// A USB device's name only under one of the keys the parser reads, with a generic registry name.
    @Test(arguments: ["kUSBProductString", "USB Product Name", "kUSBVendorString"])
    func usbNameKeysLoseTheirShortSerial(_ key: String) throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.usbDevices.firstIndex { $0.node.properties.values["USB Serial Number"] != nil })
        var values = raw.usbDevices[index].node.properties.values
        for name in ["kUSBProductString", "USB Product Name", "kUSBVendorString", "USB Vendor Name"] {
            values[name] = nil
        }
        values["USB Serial Number"] = .string("1234")
        values["kUSBSerialNumberString"] = .string("1234")
        values[key] = .string("Drive 1234")
        raw.usbDevices[index].node.properties = PropertyBag(values)
        raw.usbDevices[index].node.name = "IOUSBHostDevice"
        for interface in raw.usbDevices[index].interfaces.indices { raw.usbDevices[index].interfaces[interface].name = nil }
        let json = text(try Exporter.rawJSON(raw, redact: true))
        #expect(json.contains("Drive REDACTED") && !json.contains("Drive 1234"))
    }

    /// Two entries that share a serial (a hub's two halves, say) each name it: neither name
    /// counts as another device's, so the serial is kept.
    @Test func serialsSharedByTheirOwnPartsAreKept() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let indices = raw.usbDevices.indices.filter { raw.usbDevices[$0].node.properties.values["USB Serial Number"] != nil }
        try #require(indices.count >= 2)
        for (index, name) in zip(indices, ["Drive SN12345", "Drive SN12345 Hub"]) {
            var values = raw.usbDevices[index].node.properties.values
            values["USB Serial Number"] = .string("SN12345")
            values["USB Product Name"] = .string(name)
            raw.usbDevices[index].node.properties = PropertyBag(values)
            raw.usbDevices[index].node.name = name
        }
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.allDevices.filter { $0.device.serialNumber == "SN12345" }.count == 2)
        #expect(Exporter.serialsInNames(of: snapshot).contains("SN12345"))
    }

    /// The two halves may report the serial in different case; it is still one serial.
    @Test func serialsSharedInAnotherCaseAreKept() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let indices = raw.usbDevices.indices.filter { raw.usbDevices[$0].node.properties.values["USB Serial Number"] != nil }
        try #require(indices.count >= 2)
        for (index, (serial, name)) in zip(indices, [("SN12345", "Drive SN12345"), ("sn12345", "Drive SN12345 Hub")]) {
            var values = raw.usbDevices[index].node.properties.values
            values["USB Serial Number"] = .string(serial)
            values["USB Product Name"] = .string(name)
            raw.usbDevices[index].node.properties = PropertyBag(values)
            raw.usbDevices[index].node.name = name
        }
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.allDevices.contains { $0.device.serialNumber == "sn12345" })
        #expect(Exporter.serialsInNames(of: snapshot).contains("SN12345"))
    }

    /// A display named after a 4-digit serial: its event id carries the serial, and the title names it.
    @Test func displayNamedAfterAShortSerialIsRedactedInItsEvents() {
        let event = ConnectionEvent(id: "displayDisconnected:display:610:ae3a:8544:1790000000000", date: S.date,
                                    kind: .displayDisconnected, title: "Studio Display 8544 disconnected",
                                    detail: "3840 × 2160 @ 60 Hz", deviceID: "display:610:ae3a:8544")
        let redacted = Exporter.redacted(event)
        #expect(redacted.title == "Studio Display REDACTED disconnected")
        #expect(redacted.detail == "3840 × 2160 @ 60 Hz")
    }

    /// The raw capture knows the names of displays and chargers, so a short serial in them goes too.
    @Test func rawDisplayAndChargerNamesLoseTheirShortSerials() throws {
        let display = text(try Exporter.rawJSON(try displayNamedAfterItsSerial(8544), redact: true))
        #expect(display.contains("Studio Display") && !display.contains("Studio Display 8544"))
        let charger = text(try Exporter.rawJSON(try chargerNamedAfterItsSerial("1234"), redact: true))
        #expect(charger.contains("Charger REDACTED") && !charger.contains("Charger 1234"))
    }

    /// A serial in the vendor's name ("Vendor 1234") is removed as one in the product name is.
    @Test func shortSerialsInTheVendorNameAreRedacted() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.usbDevices.firstIndex { $0.node.properties.values["USB Serial Number"] != nil })
        var values = raw.usbDevices[index].node.properties.values
        values["USB Serial Number"] = .string("1234")
        values["USB Vendor Name"] = .string("Vendor 1234")
        raw.usbDevices[index].node.properties = PropertyBag(values)
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.allDevices.contains { $0.device.vendorName == "Vendor 1234" })
        #expect(!text(try Exporter.json(snapshot, redact: true)).contains("Vendor 1234"))
        #expect(!text(try JSONEncoder().encode(WidgetPayload(snapshot: snapshot))).contains("Vendor 1234"))
        #expect(!text(try Exporter.rawJSON(raw, redact: true)).contains("Vendor 1234"))
        #expect(Exporter.serialsInNames(of: snapshot).contains("1234"))
    }

    /// A charger is on the Mac and on its port, and a display has a device row of the same name:
    /// a name met twice is still only its own, so the serial is kept for after unplug.
    @Test func chargerAndDisplaySerialsInTheirNamesAreKept() throws {
        let charger = TopologyBuilder.build(try chargerNamedAfterItsSerial("C4H12345"))
        #expect(charger.power.charger?.name == "Charger C4H12345")
        #expect(Exporter.serialsInNames(of: charger).contains("C4H12345"))
        let display = TopologyBuilder.build(try displayNamedAfterItsSerial(12345))
        #expect(display.allDevices.contains { $0.device.name == "Studio Display 12345" })
        #expect(Exporter.serialsInNames(of: display).contains("12345"))
    }

    /// A serial that another connected device's name holds as a word is not kept after unplug,
    /// where it would turn "USB3.1 Hub" into "REDACTED.1 Hub".
    @Test func serialsOtherNamesHoldAreNotKept() throws {
        let snapshot = TopologyBuilder.build(try captureWithSerialInName("USB3"))
        #expect(snapshot.allDevices.contains { $0.device.name == "USB3.1 Hub" })
        #expect(!Exporter.serialsInNames(of: snapshot).contains("USB3"))
        #expect(Exporter.serialsInNames(of: TopologyBuilder.build(try captureWithSerialInName("USB7"))).contains("USB7"))
    }

    /// A serial padded with spaces (from a snapshot not built by the parser, which trims) is
    /// matched trimmed in other names too.
    @Test func paddedSerialsOtherNamesHoldAreNotKept() throws {
        let built = TopologyBuilder.build(try captureWithSerialInName("USB3"))
        let json = text(try JSONEncoder().encode(built))
        #expect(json.contains(#""serialNumber":"USB3""#))
        let padded = json.replacingOccurrences(of: #""serialNumber":"USB3""#, with: #""serialNumber":" USB3 ""#)
        let snapshot = try JSONDecoder().decode(HostSnapshot.self, from: Data(padded.utf8))
        #expect(snapshot.allDevices.contains { $0.device.serialNumber == " USB3 " })
        #expect(Exporter.serialsInNames(of: snapshot).isDisjoint(with: [" USB3 ", "USB3"]))
    }

    /// Short device serials in a name are removed, although a display's 4-digit serial is not.
    @Test(arguments: ["1A2B3", "12345", "C0DE", "SN12"])
    func shortDeviceSerialsInNamesAreRedacted(_ serial: String) throws {
        let snapshot = TopologyBuilder.build(try captureWithSerialInName(serial))
        #expect(snapshot.allDevices.contains { $0.device.name == "Drive \(serial)" })
        #expect(!text(try Exporter.json(snapshot, redact: true)).contains("Drive \(serial)"))
        #expect(!Exporter.markdown(snapshot, redact: true).contains("Drive \(serial)"))
        let payload = text(try JSONEncoder().encode(WidgetPayload(snapshot: snapshot)))
        #expect(!payload.contains("Drive \(serial)"))
        #expect(Exporter.serialsInNames(of: snapshot).contains(serial))
    }

    /// Display serial 8544 is "2160" in hex: a resolution or a year must not match a display's short number.
    @Test func shortDisplaySerialsStayOutOfFreeText() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.displays.firstIndex { ($0.serialNumber ?? 0) > 999 })
        raw.displays[index].serialNumber = 8544
        var snapshot = TopologyBuilder.build(raw)
        #expect(!Exporter.textSerials(in: snapshot).contains("2160"))
        snapshot.diagnostics.append(Diagnostic(id: "res", kind: .flakyConnection, severity: .info,
                                               title: "Runs at 3840 × 2160 since 2026", detail: ""))
        #expect(Exporter.redacted(snapshot).diagnostics.last?.title == "Runs at 3840 × 2160 since 2026")
        #expect(Exporter.markdown(snapshot).contains("3840 × 2160"))
        let event = ConnectionEvent(id: "1", date: S.date, kind: .displayConnected,
                                    title: "LG UltraFine connected", detail: "3840 × 2160 @ 60 Hz")
        #expect(Exporter.redacted(event, serialsFrom: [snapshot]).detail == "3840 × 2160 @ 60 Hz")
        // A display's long serial is still removed from free text.
        let long = String(0x2C41_09F3)
        var named = event
        named.detail = "Panel \(long)"
        #expect(Exporter.redacted(named, serialsFrom: [S.snapshot(.studioDesk)]).detail == "Panel REDACTED")
    }

    /// A display event's id ends in its serial: a 4-digit one is redacted in the id but
    /// left in the text, where it would match a resolution.
    @Test func shortDisplaySerialInAnEventIDStaysOutOfItsText() {
        let event = ConnectionEvent(id: "displayConnected:display:610:ae3a:2160:1790000000000", date: S.date,
                                    kind: .displayConnected, title: "LG UltraFine connected",
                                    detail: "3840 × 2160 @ 60 Hz", deviceID: "display:610:ae3a:2160")
        let redacted = Exporter.redacted(event)
        #expect(redacted.deviceID == "display:610:ae3a:REDACTED")
        #expect(redacted.detail == "3840 × 2160 @ 60 Hz")
    }

    /// A number under a serial key in a raw capture is a display serial, so a 4-digit one stays in other text.
    @Test func shortNumberSerialKeysStayOutOfRawText() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.usbDevices.firstIndex { $0.node.properties.values["USB Serial Number"] != nil })
        var values = raw.usbDevices[index].node.properties.values
        values["DisplaySerialNumber"] = .int(2160)
        values["PreferredMode"] = .string("3840 × 2160")
        raw.usbDevices[index].node.properties = PropertyBag(values)
        let json = text(try Exporter.rawJSON(raw, redact: true))
        #expect(json.contains("3840 × 2160"))
        #expect(!json.contains("\"DisplaySerialNumber\" : 2160"))
    }

    /// A 5-digit display serial cannot be a resolution or a year, so it is still removed from text.
    @Test func fiveDigitDisplaySerialsAreRedacted() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.displays.firstIndex { ($0.serialNumber ?? 0) > 999 })
        raw.displays[index].serialNumber = 12345
        var snapshot = TopologyBuilder.build(raw)
        snapshot.diagnostics.append(Diagnostic(id: "panel", kind: .flakyConnection, severity: .info,
                                               title: "Panel 12345 flickers", detail: ""))
        #expect(Exporter.redacted(snapshot).diagnostics.last?.title == "Panel REDACTED flickers")
    }

    /// A serial without a digit (an ordinary word), or one that is only part of a word of its name, is not kept.
    @Test(arguments: [("Generic", "Generic Card Reader", "Kingston"), ("Card", "SD Card Reader", "Generic"),
                      ("Data7", "Data7Traveler 3.0", "Kingston")])
    func serialsThatAreNotTheirOwnWordAreNotKept(_ serial: String, _ product: String, _ vendor: String) throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.usbDevices.firstIndex { $0.node.properties.values["USB Serial Number"] != nil })
        var values = raw.usbDevices[index].node.properties.values
        values["USB Serial Number"] = .string(serial)
        values["USB Product Name"] = .string(product)
        values["USB Vendor Name"] = .string(vendor)
        raw.usbDevices[index].node.properties = PropertyBag(values)
        raw.usbDevices[index].node.name = product
        let snapshot = TopologyBuilder.build(raw)
        let device = try #require(snapshot.allDevices.first { $0.device.serialNumber == serial }?.device)
        #expect(device.name == product && device.vendorName == vendor)
        #expect(!Exporter.serialsInNames(of: snapshot).contains(serial))
    }

    /// A 4-digit device serial ("2160", "2026") stays out of free text, where it would match a
    /// resolution or a year. A 5-digit one is still removed (`shortDeviceSerialsInNamesAreRedacted`).
    @Test func fourDigitDeviceSerialsStayOutOfFreeText() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let indices = raw.usbDevices.indices.filter { raw.usbDevices[$0].node.properties.values["USB Serial Number"] != nil }
        try #require(indices.count >= 2)
        for (index, serial) in zip(indices, ["2160", "2026"]) {
            var values = raw.usbDevices[index].node.properties.values
            values["USB Serial Number"] = .string(serial)
            raw.usbDevices[index].node.properties = PropertyBag(values)
        }
        var snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.machine.name.contains("2026"))
        snapshot.diagnostics.append(Diagnostic(id: "res", kind: .flakyConnection, severity: .info,
                                               title: "Runs at 3840 × 2160", detail: ""))
        #expect(Exporter.redacted(snapshot).diagnostics.last?.title == "Runs at 3840 × 2160")
        #expect(Exporter.markdown(snapshot).contains(snapshot.machine.name))
    }

    /// A serial the device does not put in its name ("Generic") is not kept for later redaction.
    @Test func serialsNotInTheirOwnNameAreNotKept() throws {
        var raw = DemoScenario.studioDesk.raw(at: S.date)
        let index = try #require(raw.usbDevices.firstIndex { $0.node.properties.values["USB Serial Number"] != nil })
        var values = raw.usbDevices[index].node.properties.values
        values["USB Serial Number"] = .string("Generic")
        raw.usbDevices[index].node.properties = PropertyBag(values)
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.allDevices.contains { $0.device.serialNumber == "Generic" })
        #expect(!Exporter.serialsInNames(of: snapshot).contains("Generic"))
    }

    // MARK: EDID

    @Test func malformedEDIDIsDropped() {
        var short = [UInt8](repeating: 0, count: 100)
        short[12...15] = [0x12, 0x34, 0x56, 0x78]
        #expect(Exporter.redactedEDID(Data(short)).isEmpty)
        var long = [UInt8](repeating: 0, count: 200)
        long[150...153] = [0x12, 0x34, 0x56, 0x78]
        let redacted = Exporter.redactedEDID(Data(long))
        #expect(redacted.count == 128)
        #expect(redacted[12..<16].allSatisfy { $0 == 0 })
    }

    @Test func displayIDBlocksThatCannotBeWalkedAreBlanked() {
        // Byte 126 says no extensions, block 1 is DisplayID with a section length past its end.
        var bytes = [UInt8](repeating: 0, count: 256)
        bytes[128] = 0x70
        bytes[130] = 0xFF
        bytes[140...143] = [0x12, 0x34, 0x56, 0x78]
        let redacted = [UInt8](Exporter.redactedEDID(Data(bytes)))
        #expect(redacted[129..<255].allSatisfy { $0 == 0 })
        #expect(redacted[128..<256].reduce(0) { ($0 + Int($1)) & 0xFF } == 0)
        // A data block that overruns its section blanks the rest of the section.
        bytes = [UInt8](repeating: 0, count: 256)
        bytes[126] = 1
        bytes[128] = 0x70
        bytes[130] = 20
        bytes[133...135] = [0x20, 0, 40]
        bytes[136...140] = [1, 2, 3, 4, 5]
        let overrun = [UInt8](Exporter.redactedEDID(Data(bytes)))
        #expect(overrun[133..<153].allSatisfy { $0 == 0 })
        // Zeros in the middle of a section end the walk; what follows is blanked too.
        bytes = [UInt8](repeating: 0, count: 256)
        bytes[126] = 1
        bytes[128] = 0x70
        bytes[130] = 20
        bytes[136...138] = [0x20, 0, 9]
        bytes[144...147] = [0xDE, 0xAD, 0xBE, 0xEF]
        let padded = [UInt8](Exporter.redactedEDID(Data(bytes)))
        #expect(padded[133..<153].allSatisfy { $0 == 0 })
        // A data block whose serial lies past the end of its section.
        bytes = [UInt8](repeating: 0, count: 256)
        bytes[126] = 1
        bytes[128] = 0x70
        bytes[130] = 5
        bytes[133...135] = [0x20, 0, 12]
        bytes[141...144] = [0xDE, 0xAD, 0xBE, 0xEF]
        let past = [UInt8](Exporter.redactedEDID(Data(bytes)))
        #expect(past[141..<145].allSatisfy { $0 == 0 })
        #expect(past[128..<256].reduce(0) { ($0 + Int($1)) & 0xFF } == 0)
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
