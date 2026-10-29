import Foundation
import Testing
@testable import BusStopCore

/// A real capture: a MacBook Pro (M5 Max, macOS 27.0.1) with a Dell U4025QW
/// monitor on Thunderbolt, its webcam plugged into the monitor
/// (`Fixtures/DellU4025QW.json`, saved with `busstop --raw`, redacted).
///
/// The monitor's Thunderbolt chip (Intel JHL8440) tunnels its USB 3 hub
/// (8087:0B40, with a 1D5C:5801 USB 2 half) to the Mac's own controller, and
/// the monitor heads the port's tree as a display, so that root hub folds
/// into it (rule A). Behind it sits one Realtek 4-port hub (0483/5483) with
/// two more Realtek hubs and the 2.5G Ethernet on captive ports, and the
/// webcam and two Realtek "USB2.0 HID" devices on the lower hubs' standard
/// ports. The capture predates `kUSBContainerID`, so the Realtek hubs stay;
/// the container tests add IDs to show what rule F does with them.
@Suite("Topology: Dell U4025QW capture")
struct DellU4025QWTests {
    static let portKey = PortKey(type: 2, number: 3)

    static func raw() throws -> RawSnapshot {
        let url = try #require(Bundle.module.url(forResource: "DellU4025QW", withExtension: "json"))
        return try Exporter.decodeRaw(Data(contentsOf: url))
    }

    /// The capture with `kUSBContainerID` set on the USB records with these
    /// registry IDs.
    static func raw(containers: [UInt64: String]) throws -> RawSnapshot {
        var raw = try raw()
        for index in raw.usbDevices.indices {
            if let container = containers[raw.usbDevices[index].id] {
                raw.usbDevices[index].node.properties["kUSBContainerID"] = .string(container)
            }
        }
        return raw
    }

    static func snapshot(foldsDockParts: Bool = true) throws -> HostSnapshot {
        TopologyBuilder.build(try raw(), options: BuildOptions(), foldsDockParts: foldsDockParts)
    }

    static func monitor(in snapshot: HostSnapshot) throws -> DeviceNode {
        try #require(snapshot.port(portKey)?.devices.first { $0.bus == .thunderbolt })
    }

    static let rootHub = "usb:02200000:8087:0b40"        // A: tunnelled root hub (with the 1D5C USB 2 half)
    static let realtekHub = "usb:02240000:0bda:0483"     // the one hub on the root hub
    static let lowerHub1 = "usb:02241000:0bda:0483"      // captive on the Realtek hub
    static let lowerHub2 = "usb:02242000:0bda:0483"      // captive on the Realtek hub
    static let ethernet = "usb:02243000:0bda:8156"       // captive on the Realtek hub
    // On standard ports of the lower hubs: the monitor's USB ports.
    static let webcam = "usb:02141400:046d:082d"
    static let hid1100 = "usb:02141500:0bda:1100"
    static let hid1101 = "usb:02142400:0bda:1101"

    /// Registry IDs of the USB records, both halves of each merged hub.
    static let rootRecords: [UInt64] = [4_294_971_823, 4_294_971_352]
    static let chipRecords: [UInt64] = [4_294_971_944, 4_294_971_860, 4_294_972_297, 4_294_972_338,
                                        4_294_972_383, 4_294_972_407, 4_294_972_272]
    static let webcamRecord: UInt64 = 4_294_972_429

    static let monitorContainer = "6A1F0E43-9B2C-4D8A-8E2F-1C3B5D7E9F00"
    static let otherContainer = "0B4F1A3C-77D2-4E19-9F0A-2C6E8B1D5A47"

    @Test func theMonitorIsAThunderboltDisplay() throws {
        let monitor = try Self.monitor(in: Self.snapshot())
        #expect(monitor.kind == .display)
        #expect(monitor.name == "U4025QW")
    }

    /// Without container IDs only the tunnelled root hub is known to be built
    /// in: the Realtek hub sits on a root port, whose captive flags are not
    /// evidence, so it stays with everything behind it.
    @Test func withoutContainerIDsOnlyTheRootHubFolds() throws {
        let monitor = try Self.monitor(in: Self.snapshot())
        #expect(monitor.internalParts?.map(\.id) == [Self.rootHub])
        let usb = monitor.children.filter { $0.bus == .usb }
        #expect(usb.map(\.id) == [Self.realtekHub])
        #expect(usb.first?.internalParentID == Self.rootHub)
    }

    /// Counts are drawn devices only: 8 below the monitor before (as the
    /// reporter's map showed), 7 once the root hub folds.
    @Test func countsLeaveOutTheRootHub() throws {
        let folded = try Self.snapshot()
        let unfolded = try Self.snapshot(foldsDockParts: false)
        #expect(try Self.monitor(in: unfolded).descendantCount == 8)
        #expect(try Self.monitor(in: folded).descendantCount == 7)
        #expect(unfolded.port(Self.portKey)?.deviceCount == 9)
        #expect(folded.port(Self.portKey)?.deviceCount == 8)
    }

    /// Folding moves devices, not power: every figure stays as it was.
    @Test func powerIsUnchanged() throws {
        let folded = try Self.monitor(in: Self.snapshot())
        let unfolded = try Self.monitor(in: Self.snapshot(foldsDockParts: false))
        #expect(folded.rolledUpMilliwatts == unfolded.rolledUpMilliwatts)
        #expect(folded.downstreamMilliwatts == unfolded.downstreamMilliwatts)
    }

    /// When the hub chips and the Ethernet report the root hub's container
    /// ID, they fold too, and the devices on the monitor's ports (a webcam
    /// of another product, two HID devices with none) hang off the monitor.
    @Test func chipsSharingTheRootHubsContainerFold() throws {
        var containers: [UInt64: String] = [Self.webcamRecord: Self.otherContainer]
        for id in Self.rootRecords + Self.chipRecords { containers[id] = Self.monitorContainer }
        let raw = try Self.raw(containers: containers)
        let monitor = try Self.monitor(in: TopologyBuilder.build(raw))
        #expect(Set((monitor.internalParts ?? []).map(\.id))
                == [Self.rootHub, Self.realtekHub, Self.lowerHub1, Self.lowerHub2, Self.ethernet])
        let parents = Dictionary(uniqueKeysWithValues: monitor.children.filter { $0.bus == .usb }
            .map { ($0.id, $0.internalParentID ?? "monitor") })
        #expect(parents == [Self.webcam: Self.lowerHub1, Self.hid1100: Self.lowerHub1, Self.hid1101: Self.lowerHub2])
        #expect(monitor.descendantCount == 3)
        DockPartsInvariantTests.check(raw)
    }

    /// Hub chips that share a container ID only with each other (a chip
    /// maker's default, say) are not tied to the monitor, and stay.
    @Test func chipsSharingOnlyAmongThemselvesStay() throws {
        var containers: [UInt64: String] = [:]
        for id in Self.rootRecords { containers[id] = Self.monitorContainer }
        for id in Self.chipRecords { containers[id] = Self.otherContainer }
        let monitor = try Self.monitor(in: TopologyBuilder.build(try Self.raw(containers: containers)))
        #expect(monitor.internalParts?.map(\.id) == [Self.rootHub])
        #expect(monitor.children.filter { $0.bus == .usb }.map(\.id) == [Self.realtekHub])
    }
}
