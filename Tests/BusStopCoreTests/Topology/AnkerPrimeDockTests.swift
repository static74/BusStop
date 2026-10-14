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
@Suite("Topology: Anker Prime TB5 dock capture")
struct AnkerPrimeDockTests {
    static func snapshot() throws -> HostSnapshot {
        let url = try #require(Bundle.module.url(forResource: "AnkerPrimeTB5", withExtension: "json"))
        return TopologyBuilder.build(try Exporter.decodeRaw(Data(contentsOf: url)))
    }

    static func dock(in snapshot: HostSnapshot) throws -> DeviceNode {
        try #require(snapshot.ports.flatMap { $0.devices }.first { $0.name.hasPrefix("Prime Docking Station") })
    }

    @Test func usbDevicesNestUnderTheDock() throws {
        let snapshot = try Self.snapshot()
        let port = try #require(snapshot.ports.first { $0.devices.contains { $0.name.hasPrefix("Prime Docking") } })
        #expect(port.label.location == "Left Center")
        let names = Set(try Self.dock(in: snapshot).flattened().map(\.device.name))
        for name in ["Keychron Q3 Pro", "Stream Deck Plus", "iPad", "USB Storage", "Magic Keyboard with Touch ID"] {
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

    @Test func rootHubsFromDifferentVendorsMerge() throws {
        let dock = try Self.dock(in: Self.snapshot())
        let hubs = dock.children.filter { $0.deviceClass == DeviceClassifier.USBClass.hub }
        #expect(hubs.map(\.name) == ["USB3 HUB"])
    }

    @Test func companionHubsBelowTheRootMerge() throws {
        let tree = try Self.dock(in: Self.snapshot()).flattened().map(\.device)
        // Every USB 2 half has been folded into its SuperSpeed half.
        #expect(tree.filter { $0.name == "4-Port USB 2.0 Hub" }.isEmpty)
        #expect(tree.filter { $0.name == "USB2.0 Hub" }.isEmpty)
        #expect(tree.filter { $0.name == "4-Port USB 3.0 Hub" }.count == 3)
        #expect(tree.filter { $0.name == "USB3.1 Hub" }.count == 4)
        // The Stream Deck's hub is the Realtek pair on ports 1 → 2.
        let streamDeckHub = try #require(tree.first { $0.children.contains { $0.name == "Stream Deck Plus" } })
        #expect(streamDeckHub.name == "4-Port USB 3.0 Hub")
    }
}
