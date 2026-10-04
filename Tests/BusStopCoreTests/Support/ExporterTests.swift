import Foundation
import Testing
@testable import BusStopCore

@Suite("Exporter")
struct ExporterTests {
    typealias F = SupportFixtures

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private func leaked(_ output: String) -> [String] {
        F.secrets.filter { output.contains($0) }
    }

    // MARK: JSON

    @Test func jsonIsPrettySortedAndISO8601() throws {
        let output = text(try Exporter.json(F.studioDesk(), redact: false))
        #expect(output.contains("\"capturedAt\" : \"2026-10-04T12:00:00Z\""))
        #expect(output.contains("\n  \"diagnostics\" : ["))
        #expect(output.contains("\"generation\" : \"Thunderbolt / USB4\""))
        #expect(!output.contains("\\/"))
        let capturedAt = try #require(output.range(of: "\"capturedAt\""))
        let ports = try #require(output.range(of: "\"ports\""))
        #expect(capturedAt.lowerBound < ports.lowerBound)
        // Deterministic.
        #expect(try Exporter.json(F.studioDesk()) == Exporter.json(F.studioDesk()))
    }

    @Test func jsonRoundTripsWithoutRedaction() throws {
        let snapshot = F.studioDesk()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HostSnapshot.self, from: Exporter.json(snapshot, redact: false))
        #expect(decoded == snapshot)
    }

    @Test func jsonRedactsSerials() throws {
        let plain = text(try Exporter.json(F.studioDesk(), redact: false))
        #expect(plain.contains("S6XYZ123"))
        #expect(plain.contains("C0ABC4567"))
        #expect(plain.contains("987654"))

        let output = text(try Exporter.json(F.studioDesk(), redact: true))
        #expect(leaked(output).isEmpty, "leaked: \(leaked(output))")
        #expect(output.contains("REDACTED"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let redacted = try decoder.decode(HostSnapshot.self, from: Exporter.json(F.studioDesk()))
        #expect(redacted.displays.allSatisfy { $0.serialNumber == nil })
        #expect(redacted.displays.first?.id == "display:1552:41006:REDACTED")
        #expect(redacted.power.charger?.serialNumber == "REDACTED")
        #expect(redacted.ports[0].charger?.serialNumber == "REDACTED")
        let t9 = try #require(redacted.device(id: "usb:0x01110000:04e8:61fb"))
        #expect(t9.serialNumber == "REDACTED")
        #expect(t9.properties?["USB Serial Number"] == "REDACTED")
        #expect(t9.properties?["idVendor"] == 1256)
        #expect(redacted.ports[1].properties?["ConnectionUUID"] == "REDACTED")
        #expect(redacted.ports[1].properties?["PortTypeDescription"] == "USB-C")
        // Devices without a serial stay without one.
        #expect(redacted.device(id: "usb:0x01120000:05ac:029c")?.serialNumber == nil)
    }

    @Test func redactionReachesNestedValues() {
        let bag: PropertyBag = [
            "Metadata": ["Serial Number": "ABC123", "Product": "Drive"],
            "List": [["serial-number": .data(Data([1, 2, 3]))], "plain"],
            "ConnectionUUID": "1234",
            "SerialSignal": 5,
            "Name": "Keep",
        ]
        let redacted = Exporter.redacted(bag)
        #expect(redacted["Metadata"] == ["Serial Number": "REDACTED", "Product": "Drive"])
        #expect(redacted["List"] == [["serial-number": "REDACTED"], "plain"])
        #expect(redacted["ConnectionUUID"] == "REDACTED")
        #expect(redacted["SerialSignal"] == "REDACTED")
        #expect(redacted["Name"] == "Keep")
        #expect(Exporter.isSensitiveKey("kUSBSerialNumberString"))
        #expect(!Exporter.isSensitiveKey("UUID"))
    }

    @Test func edidSerialFieldsAreBlanked() throws {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[0...7] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        bytes[12...15] = [0x78, 0x56, 0x34, 0x12]
        // Display serial number descriptor at offset 72.
        bytes[72...76] = [0x00, 0x00, 0x00, 0xFF, 0x00]
        for (offset, byte) in Array("SN12345678\n  ".utf8).enumerated() { bytes[77 + offset] = byte }
        let sum = bytes[0..<127].reduce(0) { ($0 + Int($1)) & 0xFF }
        bytes[127] = UInt8((256 - sum) & 0xFF)

        let bag = Exporter.redacted(["EDID": .data(Data(bytes))])
        let redacted = try #require(bag.data("EDID"))
        #expect(redacted.count == 128)
        #expect(Array(redacted[12...15]) == [0, 0, 0, 0])
        #expect(!String(decoding: redacted, as: UTF8.self).contains("SN1234"))
        #expect(Array(redacted[0...7]) == Array(bytes[0...7]))
        #expect(redacted.reduce(0) { ($0 + Int($1)) & 0xFF } == 0)
        // Too short to be an EDID: left alone.
        #expect(Exporter.redactedEDID(Data([1, 2, 3])) == Data([1, 2, 3]))
    }

    // MARK: Markdown

    @Test func markdownReport() {
        let report = Exporter.markdown(F.studioDesk(), redact: false)
        #expect(report.hasPrefix("# MacBook Pro (14-inch, 2026, M5 Pro)\n"))
        #expect(report.contains("Captured 2026-10-04T12:00:00Z · macOS 27.0 · Mac17,9 · Apple M5 Pro"))
        #expect(report.contains("5 ports · 4 connected · 5 devices · 61 W in"))
        #expect(report.contains("## Power"))
        #expect(report.contains("- Charger: 96W USB-C Power Adapter (Apple Inc.) on Left Rear · MagSafe"))
        #expect(report.contains("- Active contract: 20 V × 4.7 A (94 W)"))
        #expect(report.contains("- Battery: Charging · 82%"))
        #expect(report.contains("| Profile | Voltage × current | Max power | Active |"))
        #expect(report.contains("| 2 | 20 V × 4.7 A | 94 W | yes |"))
        #expect(report.contains("### Left Center · USB-C"))
        #expect(report.contains("### Left Front · USB-C\n\n- Status: empty"))
        #expect(report.contains("- Devices:\n  - **CalDigit TS4** (Dock) · Thunderbolt / USB4 @ 40 Gb/s · 5 W allocated · 2 devices"))
        #expect(report.contains("\n    - **Samsung T9** (Storage) · USB 3.2 Gen 2 @ 10 Gb/s · 4.5 W allocated"))
        #expect(report.contains("serial S6XYZ123"))
        #expect(report.contains("## Other devices"))
        #expect(report.contains("## Displays"))
        #expect(report.contains("| Studio Display | 5120 × 2880 @ 60 Hz | Left Center · USB-C | DisplayPort | 987654 |"))
        #expect(report.contains("## Diagnostics\n\n- **Warning:** Flash Drive is running at USB 2 speed"))
        #expect(report.contains("  - Suggestion: Try another cable."))
        #expect(report.hasSuffix("\n"))
        #expect(!report.hasSuffix("\n\n"))
        #expect(!report.contains("\n\n\n"))
        #expect(report.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy { !$0.hasSuffix(" ") })
    }

    @Test func markdownRedactsSerials() {
        let report = Exporter.markdown(F.studioDesk())
        #expect(leaked(report).isEmpty, "leaked: \(leaked(report))")
        #expect(report.contains("serial REDACTED"))
        #expect(report.contains("- Serial number: REDACTED"))
        #expect(report.contains("| DisplayPort | REDACTED |"))
    }

    @Test func markdownEscapesFormatting() {
        let device = F.usbDevice("usb:x", "Hub *Pro* | 7_port", kind: .hub, bps: 5_000_000_000, selfPowered: true)
        let report = Exporter.markdown(F.snapshot(ports: [F.usbC(1, "Left Center", devices: [device])]))
        #expect(report.contains("**Hub \\*Pro\\* \\| 7\\_port** (Hub)"))
        #expect(report.contains("No problems found."))
    }

    // MARK: Raw capture

    @Test func rawJSONRoundTrip() throws {
        let raw = F.rawCapture()
        let data = try Exporter.rawJSON(raw, redact: false)
        #expect(try Exporter.decodeRaw(data) == raw)
        #expect(text(data).contains("\"computerName\" : \"Jordan's MacBook Neo\""))
    }

    @Test func rawJSONRedactsEverywhere() throws {
        let data = try Exporter.rawJSON(F.rawCapture())
        let output = text(data)
        #expect(leaked(output).isEmpty, "leaked: \(leaked(output))")
        #expect(!output.contains("computerName"))

        let decoded = try Exporter.decodeRaw(data)
        #expect(decoded.machine.computerName == nil)
        #expect(decoded.machine.model == "Mac17,5")
        #expect(decoded.displays.allSatisfy { $0.serialNumber == nil })
        #expect(decoded.usbDevices[0].node.properties.string("USB Serial Number") == "REDACTED")
        #expect(decoded.usbDevices[0].node.properties.int("UsbLinkSpeed") == 480_000_000)
        #expect(decoded.portNodes[1].properties.bag("Metadata")?.string("Serial Number") == "REDACTED")
        #expect(decoded.battery?.bag("AdapterDetails")?.string("SerialString") == "REDACTED")
        #expect(decoded.battery?.bag("AdapterDetails")?.int("Watts") == 30)
        #expect(decoded.adapter?.string("SerialNumber") == "REDACTED")
        #expect(decoded.thunderboltSwitches[0].ports[0].properties.bag("DROM")?.string("Serial") == "REDACTED")
        #expect(decoded.portNodes[0].properties.string("ConnectionUUID") == "REDACTED")
        // Non-sensitive data survives.
        #expect(decoded.portNodes[0].properties.data("FW Version") == Data([0x00, 0x99, 0x30, 0x00]))
        #expect(decoded.smcChannels == F.rawCapture().smcChannels)
        #expect(decoded.captureNotes == ["SMC unavailable"])
    }

    @Test func decodeRawToleratesMissingFields() throws {
        let json = """
        {
          "capturedAt": "2026-10-04T12:00:00Z",
          "machine": { "model": "Mac16,10" },
          "portNodes": [ { "id": 7, "name": "Port-USB-C", "className": "IOPort" } ],
          "thunderboltSwitches": [ { "node": { "id": 9 } } ],
          "usbDevices": [ { "node": { "id": 11, "className": "IOUSBHostDevice", "name": "Drive" } } ],
          "displays": [ { "id": 3 } ]
        }
        """
        let raw = try Exporter.decodeRaw(Data(json.utf8))
        #expect(raw.schemaVersion == RawSnapshot.currentSchemaVersion)
        #expect(raw.capturedAt == F.date)
        #expect(raw.machine.model == "Mac16,10")
        #expect(raw.machine.osVersion == "")
        #expect(raw.machine.hasBattery == false)
        #expect(raw.portNodes.first?.properties.isEmpty == true)
        #expect(raw.portNodes.first?.classChain == [])
        #expect(raw.thunderboltSwitches.first?.ports == [])
        #expect(raw.usbDevices.first?.interfaces == [])
        #expect(raw.displays.first?.isBuiltin == false)
        #expect(raw.smcChannels.isEmpty)
        #expect(raw.captureNotes.isEmpty)
        #expect(raw.battery == nil)
    }

    @Test func decodeRawRejectsGarbage() {
        #expect(throws: (any Error).self) { try Exporter.decodeRaw(Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try Exporter.decodeRaw(Data("[1, 2]".utf8)) }
        #expect(throws: (any Error).self) { try Exporter.decodeRaw(Data("{\"machine\": {\"model\": \"Mac\"}}".utf8)) }
    }

    // MARK: Text tree

    @Test func textTreeSnapshot() {
        let expected = """
        MacBook Pro (14-inch, 2026, M5 Pro) · macOS 27.0
        Power: 96W USB-C Power Adapter · 20 V × 4.7 A · 61 W in · Charging · 82% · 5.5 W to ports
        ├─ Left Rear · MagSafe   96W USB-C Power Adapter   ↓ 61 W
        ├─ Left Center · USB-C   Thunderbolt / USB4 @ 40 Gb/s   ↑ 5 W
        │  └─ CalDigit TS4 · 40 Gb/s · 5 W
        │     ├─ Samsung T9 · 10 Gb/s · 4.5 W
        │     └─ Magic Keyboard · 12 Mb/s · 0.5 W
        ├─ Left Front · USB-C   (empty)
        ├─ Right Rear · HDMI   HDMI
        └─ Right Center · USB-C   USB 2.0 @ 480 Mb/s   ↑ 0.5 W
           └─ Flash Drive · 480 Mb/s · 0.5 W

        Other devices
        └─ USB Receiver · 12 Mb/s · 0.1 W

        Displays
        ├─ Studio Display · 5120 × 2880 @ 60 Hz · Left Center · USB-C
        └─ Color LCD · 3024 × 1964 @ 120 Hz · built-in

        Diagnostics
        └─ Warning: Flash Drive is running at USB 2 speed

        """
        let output = Exporter.textTree(F.studioDesk())
        #expect(output == expected)
        #expect(!output.contains("\u{1B}"))
        #expect(output.split(separator: "\n").allSatisfy { !$0.hasSuffix(" ") })
    }

    @Test func textTreeForAnEmptyMac() {
        let snapshot = F.snapshot(machine: F.desktop(), power: PowerSummary())
        #expect(Exporter.textTree(snapshot) == """
        Mac mini (2024, M4 Pro) · macOS 27.0
        Power: No power readings
        └─ No ports found

        """)
    }

    @Test func textTreeCleansDeviceNames() {
        let device = F.usbDevice("usb:x", "Evil\u{1B}[31m\nName ", bps: 12_000_000)
        let output = Exporter.textTree(F.snapshot(ports: [F.usbC(1, "Left Center", devices: [device])]))
        #expect(!output.contains("\u{1B}"))
        #expect(output.contains("└─ Evil [31m Name · 12 Mb/s"))
    }
}
