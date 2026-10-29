import Foundation
import Testing
@testable import BusStopCore

/// A real capture: a MacBook Pro (M5 Max, macOS 27.0.1) with an Anker Prime
/// Thunderbolt 5 dock on Left Center, two displays and a USB hub on the dock
/// (`Fixtures/AnkerPrimeTB5.json`, saved with `busstop --raw`, redacted).
///
/// The dock's USB 3 root hub is Intel (8087:5787) and its USB 2 root hub is
/// Fresco Logic (1d5c:5801), so the two halves share no vendor. The hubs
/// below them do pair up (Realtek 0483/5483 on port 1, VIA 0822/2822 on
/// port 4), which is what ties the roots together.
///
/// Seven of the dock's own USB parts fold into the dock card (SPEC §5.4
/// "Built-in dock parts"): the tunnelled root hub, the two USB functions
/// with the dock's own vendor and product IDs, the VIA hub that holds one
/// of them on a captive port, the captive VIA hub below it and the Ethernet
/// and card reader on that hub. The Realtek hub on the dock (the Dell
/// monitor's) holds its two other chips (`HubChips`).
@Suite("Topology: Anker Prime TB5 dock capture")
struct AnkerPrimeDockTests {
    static let dockSwitchID: UInt64 = 4_295_375_469

    static func raw() throws -> RawSnapshot {
        let url = try #require(Bundle.module.url(forResource: "AnkerPrimeTB5", withExtension: "json"))
        return try Exporter.decodeRaw(Data(contentsOf: url))
    }

    static func snapshot(foldsDockParts: Bool = true) throws -> HostSnapshot {
        TopologyBuilder.build(try raw(), options: BuildOptions(), foldsDockParts: foldsDockParts)
    }

    static func dock(in snapshot: HostSnapshot) throws -> DeviceNode {
        try #require(snapshot.ports.flatMap { $0.devices }.first { $0.name.hasPrefix("Prime Docking Station") })
    }

    /// The capture with `edit` applied to the USB record with registry ID `id`.
    static func raw(editingUSB id: UInt64, _ edit: (inout RawUSBDevice) -> Void) throws -> RawSnapshot {
        var raw = try raw()
        let index = try #require(raw.usbDevices.firstIndex { $0.id == id })
        edit(&raw.usbDevices[index])
        return raw
    }

    /// The dock's parts, leaving out the hub chips folded elsewhere.
    static func partIDs(_ snapshot: HostSnapshot) -> Set<String> {
        Set(((try? dock(in: snapshot))?.internalParts ?? []).map(\.id))
    }

    // Parts, by rule (see `DockParts`).
    static let rootHub = "usb:00200000:8087:5787"          // A: tunnelled root hub (with the Fresco USB 2 half)
    static let tb5Function = "usb:00150000:291a:83b5"      // B: dock identity, 12 Mb/s on Fresco port 5
    static let viaRootHub = "usb:00240000:2109:0822"       // D: holds the 480 Mb/s identity on captive port 5
    static let primeFunction = "usb:00145000:291a:83b5"    // B: dock identity, 480 Mb/s
    static let captiveHub = "usb:00242000:2109:0822"       // C: captive below the D hub, both halves
    static let ethernet = "usb:00242400:0bda:8156"         // E: function on the captive hub
    static let cardReader = "usb:00242300:05e3:0764"       // E: function on the captive hub
    static let expectedParts: Set<String> = [rootHub, tb5Function, viaRootHub, primeFunction, captiveHub, ethernet,
                                             cardReader]
    // Hub chips: the two Realtek hubs on captive ports of the monitor's hub.
    static let realtekHub = "usb:00210000:0bda:0483"
    static let realtekChips: Set<String> = ["usb:00212000:0bda:0483", "usb:00213000:0bda:0483"]

    // MARK: - What folds

    @Test func builtInPartsFoldIntoTheDock() throws {
        let snapshot = try Self.snapshot()
        let dock = try Self.dock(in: snapshot)
        #expect(Set((dock.internalParts ?? []).map(\.id)) == Self.expectedParts)
        #expect(Self.partIDs(snapshot) == Self.expectedParts)
        #expect(snapshot.internalPartIDs == Self.expectedParts.union(Self.realtekChips))
        // Parts are a flat list in name order.
        let parts = try #require(dock.internalParts)
        #expect(parts.allSatisfy { $0.children.isEmpty && $0.internalParts == nil })
        #expect(parts.map(\.name) == parts.map(\.name).sorted { $0.lowercased() < $1.lowercased() })

        // What stays on the map: the two displays, the Realtek hub, the Cable
        // Matters billboard (a USB-C to DisplayPort cable) and the VIA hub
        // with the iPad and the keyboard behind it.
        #expect(dock.children.filter { $0.kind == .display }.map(\.name) == ["Dell U4924DW", "Gigabyte M32U"])
        #expect(Set(dock.children.filter { $0.bus == .usb }.map(\.id)) == [
            "usb:00210000:0bda:0483", "usb:00130000:0bda:5452", "usb:00241000:2109:0822",
        ])
        #expect(dock.children.map(\.name) == ["4-Port USB 3.0 Hub", "billboard", "Dell U4924DW", "Gigabyte M32U",
                                              "USB3.1 Hub"])
    }

    @Test func partsRecordWhatTheyHangOff() throws {
        let parts = try #require(try Self.dock(in: Self.snapshot()).internalParts)
        let parents = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0.internalParentID ?? "dock") })
        #expect(parents == [
            Self.rootHub: "dock",
            Self.tb5Function: Self.rootHub,
            Self.viaRootHub: Self.rootHub,
            Self.primeFunction: Self.viaRootHub,
            Self.captiveHub: Self.viaRootHub,
            Self.ethernet: Self.captiveHub,
            Self.cardReader: Self.captiveHub,
        ])
    }

    @Test func movedDevicesRecordTheirBuiltInHub() throws {
        let dock = try Self.dock(in: Self.snapshot())
        let parents = Dictionary(uniqueKeysWithValues: dock.children.map { ($0.id, $0.internalParentID ?? "dock") })
        #expect(parents["usb:00210000:0bda:0483"] == Self.rootHub)
        #expect(parents["usb:00130000:0bda:5452"] == Self.rootHub)
        #expect(parents["usb:00241000:2109:0822"] == Self.viaRootHub)
        #expect(dock.children.filter { $0.kind == .display }.allSatisfy { $0.internalParentID == nil })
    }

    @Test func noDockFunctionOrBuiltInHubIsDrawn() throws {
        let snapshot = try Self.snapshot()
        let visible = snapshot.allDevices.map(\.device)
        #expect(visible.filter { $0.bus == .usb && $0.vendorID == 0x291A }.isEmpty)
        #expect(visible.filter { Self.expectedParts.contains($0.id) }.isEmpty)
        #expect(!visible.contains { $0.name == "USB3 HUB" })
    }

    @Test func externalHubsKeepTheirDevices() throws {
        let dock = try Self.dock(in: Self.snapshot())
        let realtek = try #require(dock.children.first { $0.id == Self.realtekHub })
        #expect(Set((realtek.internalParts ?? []).map(\.id)) == Self.realtekChips)
        #expect(realtek.descendantCount == 6)
        #expect(realtek.flattened().contains { $0.device.name == "Stream Deck Plus" })
        #expect(realtek.flattened().contains { $0.device.name == "USB 10_100_1G_2_5G LAN" })
        let via = try #require(dock.children.first { $0.id == "usb:00241000:2109:0822" })
        #expect(via.children.map(\.name) == ["iPad", "USB Billboard Device", "USB3.1 Hub"])
        #expect(via.descendantCount == 6)
        #expect(via.flattened().contains { $0.device.name == "Keychron Q3 Pro" })
    }

    // MARK: - Counts and power

    /// Counts are drawn devices only: 26 below the dock before, 17 after.
    @Test func countsLeaveOutBuiltInParts() throws {
        let folded = try Self.snapshot()
        let unfolded = try Self.snapshot(foldsDockParts: false)
        #expect(try Self.dock(in: unfolded).descendantCount == 26)
        #expect(try Self.dock(in: folded).descendantCount == 17)
        let key = PortKey(type: 2, number: 1)
        #expect(unfolded.port(key)?.deviceCount == 27)
        #expect(folded.port(key)?.deviceCount == 18)
        #expect(unfolded.deviceCount == 27)
        #expect(folded.deviceCount == 18)
    }

    /// Folding moves devices, not power: every figure stays as it was.
    @Test func powerIsUnchanged() throws {
        let folded = try Self.dock(in: Self.snapshot())
        let unfolded = try Self.dock(in: Self.snapshot(foldsDockParts: false))
        #expect(folded.rolledUpMilliwatts == unfolded.rolledUpMilliwatts)
        #expect(folded.downstreamMilliwatts == unfolded.downstreamMilliwatts)
        #expect(folded.rolledUpMilliwatts == 21_540)
        let key = PortKey(type: 2, number: 1)
        #expect(try Self.snapshot().port(key)?.allocatedMilliwatts
                == Self.snapshot(foldsDockParts: false).port(key)?.allocatedMilliwatts)
    }

    @Test func partsCarryWhatTheInspectorShows() throws {
        let parts = try #require(try Self.dock(in: Self.snapshot()).internalParts)
        let byID = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0) })
        let hub = try #require(byID[Self.rootHub])
        #expect(hub.name == "USB3 HUB")
        #expect(hub.vendorName == "Intel Corporation")
        #expect(hub.link?.rateLabel == "10 Gb/s")
        let function = try #require(byID[Self.tb5Function])
        #expect(function.name == "Anker Thunderbolt 5 Docking Station")
        #expect(function.vendorName == "Anker")
        #expect(function.link?.rateLabel == "12 Mb/s")
        let ethernet = try #require(byID[Self.ethernet])
        #expect(ethernet.name == "USB 10_100 LAN")
        #expect(ethernet.vendorName == "Realtek")
        #expect(ethernet.link?.rateLabel == "5 Gb/s")
        #expect(ethernet.power?.allocatedMilliwatts ?? 0 > 0)
    }

    // MARK: - Fail closed

    /// Without the 480 Mb/s identity function the VIA hub has nothing that
    /// ties it to the dock, so only the root hub and the 12 Mb/s function fold.
    @Test func withoutTheCaptiveIdentityOnlyTheRootFolds() throws {
        var raw = try Self.raw()
        raw.usbDevices.removeAll { $0.id == 4_295_376_433 }
        let snapshot = TopologyBuilder.build(raw)
        #expect(Self.partIDs(snapshot) == [Self.rootHub, Self.tb5Function])
    }

    @Test func withoutTheTunnelledRootNothingFolds() throws {
        var raw = try Self.raw()
        raw.usbDevices.removeAll { $0.id == 4_295_375_556 }
        #expect(Self.partIDs(TopologyBuilder.build(raw)).isEmpty)
    }

    /// The Fresco USB 2 root hub, no longer a hub, cannot pair with the
    /// Intel one: everything on it stays on the map, and so does the VIA hub
    /// whose identity function hangs off the Fresco half.
    @Test func unmergedUSB2HalfLeavesOnlyTheRootHub() throws {
        let raw = try Self.raw(editingUSB: 4_295_375_554) { $0.node.properties["bDeviceClass"] = 0 }
        let snapshot = TopologyBuilder.build(raw)
        #expect(Self.partIDs(snapshot) == [Self.rootHub])
        let dock = try Self.dock(in: snapshot)
        #expect(dock.children.contains { $0.name == "USB2.0 Hub" })
    }

    @Test(arguments: [PlistValue.int(0), .string("Anker"), .int(-1), .int(1 << 40)])
    func unusableDockIdentityTurnsOffTheIdentityRules(_ value: PlistValue) throws {
        var raw = try Self.raw()
        let index = try #require(raw.thunderboltSwitches.firstIndex { $0.id == Self.dockSwitchID })
        raw.thunderboltSwitches[index].node.properties["Device Vendor ID"] = value
        #expect(Self.partIDs(TopologyBuilder.build(raw)) == [Self.rootHub])
        raw.thunderboltSwitches[index].node.properties["Device Vendor ID"] = nil
        #expect(Self.partIDs(TopologyBuilder.build(raw)) == [Self.rootHub])
    }

    /// Another switch with the same vendor and model IDs: the IDs no longer
    /// identify one device.
    @Test func sharedDockIdentityTurnsOffTheIdentityRules() throws {
        var raw = try Self.raw()
        var twin = try #require(raw.thunderboltSwitches.first { $0.id == Self.dockSwitchID })
        twin.node.id = 9_999_999
        twin.node.properties["UID"] = 1
        twin.parentSwitchID = nil
        twin.ancestry = []
        twin.ports = []
        raw.thunderboltSwitches.append(twin)
        #expect(Self.partIDs(TopologyBuilder.build(raw)) == [Self.rootHub])
    }

    /// Only one half of the captive VIA pair says captive: that hub and the
    /// functions on it stay on the map.
    @Test func captiveHubNeedsBothHalvesCaptive() throws {
        let raw = try Self.raw(editingUSB: 4_295_376_094) { $0.node.properties["USBPortType"] = 0 }
        #expect(Self.partIDs(TopologyBuilder.build(raw))
                == [Self.rootHub, Self.tb5Function, Self.viaRootHub, Self.primeFunction])
    }

    @Test(arguments: [PlistValue.string("1"), .bool(true), .double(1.5), .int(.max), .data(Data()), .array([])])
    func oddEvidenceValuesNeverCrash(_ value: PlistValue) throws {
        var raw = try Self.raw()
        for i in raw.usbDevices.indices {
            for key in ["UsbTunnel", "USBPortType", "idVendor", "idProduct", "bDeviceClass"] {
                raw.usbDevices[i].node.properties[key] = value
            }
        }
        for i in raw.thunderboltSwitches.indices {
            for key in ["Device Vendor ID", "Device Model ID"] {
                raw.thunderboltSwitches[i].node.properties[key] = value
            }
        }
        // Duplicate registry IDs, too.
        raw.usbDevices += raw.usbDevices.prefix(3)
        raw.thunderboltSwitches += raw.thunderboltSwitches.prefix(2)
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.deviceCount > 0)
    }

    // MARK: - Output

    @Test func textTreeShowsOneDockCard() throws {
        let text = Exporter.textTree(try Self.snapshot())
        let expected = """
        ├─ Left Center · USB-C   USB4 v2 / TB5 @ 80 Gb/s   140W Power Adapter   ↓ 55 W
        │  └─ Prime Docking Station (14-in-1, 8K, Thunderbolt 5) · 80 Gb/s · 22 W
        │     ├─ 4-Port USB 3.0 Hub · 10 Gb/s · 6.3 W
        │     │  ├─ Elgato Wave Neo · 480 Mb/s
        │     │  ├─ Insta360 Link 2C · 480 Mb/s
        │     │  ├─ Magic Keyboard with Touch ID · 12 Mb/s · 2.5 W
        │     │  ├─ Stream Deck Plus · 480 Mb/s · 2.5 W
        │     │  ├─ USB 10_100_1G_2_5G LAN · 5 Gb/s · 1.3 W
        │     │  └─ USB2.0 HID · 480 Mb/s
        │     ├─ billboard · 12 Mb/s · 2.5 W
        │     ├─ Dell U4924DW · 21.6 Gb/s
        │     ├─ Gigabyte M32U · 32.4 Gb/s
        │     └─ USB3.1 Hub · 10 Gb/s · 7 W
        │        ├─ iPad · 10 Gb/s · 4.5 W
        │        ├─ USB Billboard Device · 480 Mb/s
        │        └─ USB3.1 Hub · 10 Gb/s · 2.5 W
        │           ├─ Benchmark 1.0 · 12 Mb/s
        │           ├─ Keychron Q3 Pro · 12 Mb/s · 2.5 W
        │           └─ USB Billboard Device · 480 Mb/s
        ├─ Left Front · USB-C   (empty)
        """
        #expect(text.contains(expected), "\(text)")
        #expect(!text.contains("built-in"))
    }

    @Test func markdownListsTheBuiltInParts() throws {
        let markdown = Exporter.markdown(try Self.snapshot())
        // The dock's line counts drawn devices only; the parts are named below it.
        #expect(markdown.contains("22 W allocated · 17 devices · `0x8087:0x5786`"))
        #expect(!markdown.contains("built-in part"))
        #expect(markdown.contains("Built in: Anker Prime Docking Station, Anker Thunderbolt 5 Docking Station, "
            + "USB 10\\_100 LAN, USB Storage, USB3 HUB, USB3.1 Hub, USB3.1 Hub"))
    }

    @Test func jsonRoundTripKeepsTheParts() throws {
        let snapshot = try Self.snapshot()
        let decoded = try Exporter.makeDecoder().decode(HostSnapshot.self,
                                                        from: Exporter.json(snapshot, redact: false))
        #expect(decoded == snapshot)
        // Redacted: the parts are still there, and still point at each other.
        let redacted = try Exporter.makeDecoder().decode(HostSnapshot.self, from: Exporter.json(snapshot))
        let dock = try Self.dock(in: redacted)
        let parts = try #require(dock.internalParts)
        #expect(parts.count == 7)
        let ids = Set(parts.map(\.id))
        #expect((parts + dock.children).compactMap(\.internalParentID).allSatisfy(ids.contains))
    }

    /// The JSON of a snapshot with the two new fields removed, at every depth:
    /// what an export made before they existed looks like.
    static func withoutPartFields(_ data: Data) throws -> Data {
        func strip(_ value: PlistValue) -> PlistValue {
            switch value {
            case .dict(var object):
                object["internalParts"] = nil
                object["internalParentID"] = nil
                return .dict(object.mapValues(strip))
            case .array(let items):
                return .array(items.map(strip))
            default:
                return value
            }
        }
        return try JSONEncoder().encode(strip(try JSONDecoder().decode(PlistValue.self, from: data)))
    }

    @Test func exportsWithoutThePartFieldsStillDecode() throws {
        // A tree without parts encodes no part fields at all.
        let unfolded = try Self.snapshot(foldsDockParts: false)
        let plain = try Exporter.json(unfolded, redact: false)
        #expect(!String(decoding: plain, as: UTF8.self).contains("internalPart"))
        #expect(try Exporter.makeDecoder().decode(HostSnapshot.self, from: plain) == unfolded)

        // Folded, with the fields taken out: it decodes, and the dock simply
        // has no parts.
        let folded = try Self.snapshot()
        let full = try Exporter.json(folded, redact: false)
        #expect(String(decoding: full, as: UTF8.self).contains("\"internalParts\""))
        let stripped = try Exporter.makeDecoder().decode(HostSnapshot.self, from: Self.withoutPartFields(full))
        #expect(stripped.internalPartIDs.isEmpty)
        #expect(stripped.deviceCount == 18)
        #expect(try Self.dock(in: stripped).internalParts == nil)
    }

    // MARK: - Events

    /// The same hardware read with and without folding (an app update, or a
    /// part that the rules recognise only once it has enumerated) raises no
    /// connect or disconnect events either way.
    @Test func reclassificationRaisesNoEvents() throws {
        let folded = try Self.snapshot()
        let unfolded = try Self.snapshot(foldsDockParts: false)
        let date = folded.capturedAt.addingTimeInterval(2)
        #expect(SnapshotDiffer.events(from: unfolded, to: folded, at: date).isEmpty)
        #expect(SnapshotDiffer.events(from: folded, to: unfolded, at: date).isEmpty)
    }

    /// Unplugging the dock is one event, which counts the drawn devices only.
    @Test func unpluggingTheDockCountsDrawnDevices() throws {
        let folded = try Self.snapshot()
        var empty = folded
        let index = try #require(empty.ports.firstIndex { $0.key == PortKey(type: 2, number: 1) })
        empty.ports[index].devices = []
        let events = SnapshotDiffer.events(from: folded, to: empty, at: folded.capturedAt.addingTimeInterval(2))
        let disconnected = events.filter { $0.kind == .deviceDisconnected }
        #expect(disconnected.count == 1)
        // Two display rows are left to the display events.
        #expect(disconnected.first?.detail.hasSuffix("and 15 more devices") == true)
    }

    // MARK: - Hub pairs (folding off)

    @Test func rootHubsFromDifferentVendorsMerge() throws {
        let dock = try Self.dock(in: Self.snapshot(foldsDockParts: false))
        let hubs = dock.children.filter { $0.deviceClass == DeviceClassifier.USBClass.hub }
        #expect(hubs.map(\.name) == ["USB3 HUB"])
        // Folded, the merged pair is one part.
        let parts = try #require(try Self.dock(in: Self.snapshot()).internalParts)
        #expect(parts.filter { $0.deviceClass == DeviceClassifier.USBClass.hub }.map(\.name)
                == ["USB3 HUB", "USB3.1 Hub", "USB3.1 Hub"])
    }

    @Test func companionHubsBelowTheRootMerge() throws {
        let tree = try Self.dock(in: Self.snapshot(foldsDockParts: false)).flattened().map(\.device)
        // Every USB 2 half has been folded into its SuperSpeed half.
        #expect(tree.filter { $0.name == "4-Port USB 2.0 Hub" }.isEmpty)
        #expect(tree.filter { $0.name == "USB2.0 Hub" }.isEmpty)
        #expect(tree.filter { $0.name == "4-Port USB 3.0 Hub" }.count == 3)
        #expect(tree.filter { $0.name == "USB3.1 Hub" }.count == 4)
        // The Stream Deck's hub is the Realtek pair on ports 1 → 2.
        let streamDeckHub = try #require(tree.first { $0.children.contains { $0.name == "Stream Deck Plus" } })
        #expect(streamDeckHub.name == "4-Port USB 3.0 Hub")
    }

    // MARK: - Unchanged

    @Test func usbDevicesNestUnderTheDock() throws {
        let snapshot = try Self.snapshot()
        let port = try #require(snapshot.ports.first { $0.devices.contains { $0.name.hasPrefix("Prime Docking") } })
        #expect(port.label.location == "Left Center")
        let names = Set(try Self.dock(in: snapshot).flattened().map(\.device.name))
        for name in ["Keychron Q3 Pro", "Stream Deck Plus", "iPad", "Magic Keyboard with Touch ID"] {
            #expect(names.contains(name), "\(name) is not under the dock")
        }
    }

    /// Host lane 0 reports two bonded lanes with `Link Bandwidth` 800; lane 1
    /// and the dock's lane report asymmetric widths with a bandwidth of 0.
    /// The link is 80 Gb/s, as System Information says, on the port and the
    /// dock alike.
    @Test func portAndDockAgreeOnTheLinkSpeed() throws {
        let snapshot = try Self.snapshot()
        let port = try #require(snapshot.ports.first { $0.label.location == "Left Center" })
        #expect(port.link?.bitsPerSecond == 80_000_000_000)
        #expect(port.link?.isAsymmetric == false)
        #expect(try Self.dock(in: snapshot).link?.bitsPerSecond == 80_000_000_000)
    }

    @Test func tunneledDisplaysNestUnderTheDock() throws {
        let snapshot = try Self.snapshot()
        let port = try #require(snapshot.ports.first { $0.label.location == "Left Center" })
        #expect(port.devices.map(\.name) == ["Prime Docking Station (14-in-1, 8K, Thunderbolt 5)"])
        let displays = try Self.dock(in: snapshot).children.filter { $0.kind == .display }.map(\.name)
        #expect(displays.sorted() == ["Dell U4924DW", "Gigabyte M32U"])
    }
}
