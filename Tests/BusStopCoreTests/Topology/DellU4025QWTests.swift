import Foundation
import Testing
@testable import BusStopCore

/// A real capture: a MacBook Pro (M5 Max, macOS 27.0.1) with a Dell U4025QW
/// monitor on Thunderbolt, its webcam plugged into the monitor
/// (`Fixtures/DellU4025QW.json`, saved with `busstop --raw`, redacted).
///
/// The monitor's Thunderbolt chip (Intel JHL8440) tunnels its USB 3 hub
/// (8087:0B40, with a 1D5C:5801 USB 2 half) to the Mac's own controller.
/// Behind it sits one Realtek 4-port hub (0483/5483) whose devices are all
/// on captive ports: two more Realtek hubs and the 2.5G Ethernet. The
/// monitor's USB ports hang off those two hubs. The monitor heads the port's
/// tree as a display, so its tunnelled root hub (rule A) and the Realtek
/// hub cascade (rules F and G) fold into it (SPEC §5.4 "Built-in dock
/// parts"). The two Realtek "USB2.0 HID" devices are on standard ports and
/// stay.
@Suite("Topology: Dell U4025QW capture")
struct DellU4025QWTests {
    static let portKey = PortKey(type: 2, number: 3)

    static func raw() throws -> RawSnapshot {
        let url = try #require(Bundle.module.url(forResource: "DellU4025QW", withExtension: "json"))
        return try Exporter.decodeRaw(Data(contentsOf: url))
    }

    static func snapshot(foldsDockParts: Bool = true) throws -> HostSnapshot {
        TopologyBuilder.build(try raw(), options: BuildOptions(), foldsDockParts: foldsDockParts)
    }

    static func monitor(in snapshot: HostSnapshot) throws -> DeviceNode {
        try #require(snapshot.port(portKey)?.devices.first { $0.bus == .thunderbolt })
    }

    // Parts, by rule (see `DockParts`).
    static let rootHub = "usb:02200000:8087:0b40"        // A: tunnelled root hub (with the 1D5C USB 2 half)
    static let realtekHub = "usb:02240000:0bda:0483"     // F: the one hub on the root hub, all captive
    static let lowerHub1 = "usb:02241000:0bda:0483"      // G: captive on the Realtek hub
    static let lowerHub2 = "usb:02242000:0bda:0483"      // G: captive on the Realtek hub
    static let ethernet = "usb:02243000:0bda:8156"       // G: captive on the Realtek hub
    static let expectedParts: Set<String> = [rootHub, realtekHub, lowerHub1, lowerHub2, ethernet]

    // On standard ports of the lower hubs: the monitor's USB ports.
    static let webcam = "usb:02141400:046d:082d"
    static let hid1100 = "usb:02141500:0bda:1100"
    static let hid1101 = "usb:02142400:0bda:1101"

    @Test func theMonitorIsAThunderboltDisplay() throws {
        let monitor = try Self.monitor(in: Self.snapshot())
        #expect(monitor.kind == .display)
        #expect(monitor.name == "U4025QW")
    }

    @Test func builtInPartsFoldIntoTheMonitor() throws {
        let snapshot = try Self.snapshot()
        let monitor = try Self.monitor(in: snapshot)
        #expect(Set((monitor.internalParts ?? []).map(\.id)) == Self.expectedParts)
        #expect(snapshot.internalPartIDs == Self.expectedParts)
        let parts = try #require(monitor.internalParts)
        #expect(parts.allSatisfy { $0.children.isEmpty && $0.internalParts == nil })
        #expect(Set(monitor.children.filter { $0.bus == .usb }.map(\.id)) == [Self.webcam, Self.hid1100, Self.hid1101])
    }

    @Test func partsRecordWhatTheyHangOff() throws {
        let parts = try #require(try Self.monitor(in: Self.snapshot()).internalParts)
        let parents = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0.internalParentID ?? "monitor") })
        #expect(parents == [
            Self.rootHub: "monitor",
            Self.realtekHub: Self.rootHub,
            Self.lowerHub1: Self.realtekHub,
            Self.lowerHub2: Self.realtekHub,
            Self.ethernet: Self.realtekHub,
        ])
    }

    @Test func devicesOnTheMonitorsPortsRecordTheirBuiltInHub() throws {
        let monitor = try Self.monitor(in: Self.snapshot())
        let parents = Dictionary(uniqueKeysWithValues: monitor.children.filter { $0.bus == .usb }
            .map { ($0.id, $0.internalParentID ?? "monitor") })
        #expect(parents == [Self.webcam: Self.lowerHub1, Self.hid1100: Self.lowerHub1, Self.hid1101: Self.lowerHub2])
    }

    /// Counts are drawn devices only: 8 below the monitor before (as the
    /// reporter's map showed), 3 after.
    @Test func countsLeaveOutBuiltInParts() throws {
        let folded = try Self.snapshot()
        let unfolded = try Self.snapshot(foldsDockParts: false)
        #expect(try Self.monitor(in: unfolded).descendantCount == 8)
        #expect(try Self.monitor(in: folded).descendantCount == 3)
        #expect(unfolded.port(Self.portKey)?.deviceCount == 9)
        #expect(folded.port(Self.portKey)?.deviceCount == 4)
    }

    /// Folding moves devices, not power: every figure stays as it was.
    @Test func powerIsUnchanged() throws {
        let folded = try Self.monitor(in: Self.snapshot())
        let unfolded = try Self.monitor(in: Self.snapshot(foldsDockParts: false))
        #expect(folded.rolledUpMilliwatts == unfolded.rolledUpMilliwatts)
        #expect(folded.downstreamMilliwatts == unfolded.downstreamMilliwatts)
    }

    /// As a dock, the same monitor folds only its root hub: a monitor's hub
    /// chips plugged into a dock look the same (`AnkerPrimeDockTests`).
    @Test func asADockOnlyTheRootHubFolds() throws {
        var raw = try Self.raw()
        let index = try #require(raw.thunderboltSwitches.firstIndex {
            $0.node.properties.string("Device Model Name") == "U4025QW"
        })
        raw.thunderboltSwitches[index].node.properties["Device Model Name"] = "U4025QW Docking Station"
        let monitor = try Self.monitor(in: TopologyBuilder.build(raw))
        #expect(monitor.kind == .dock)
        #expect(monitor.internalParts?.map(\.id) == [Self.rootHub])
        #expect(monitor.children.filter { $0.bus == .usb }.map(\.id) == [Self.realtekHub])
    }
}
