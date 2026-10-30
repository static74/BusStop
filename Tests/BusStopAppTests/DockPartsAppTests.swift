import BusStopCore
import Foundation
import Testing
@testable import BusStopApp

/// The window on the Anker Prime TB5 capture, whose dock has five built-in
/// parts folded into it: the Cables list, the link page, search, VoiceOver
/// text and the selection all treat the dock as one device.
@MainActor
@Suite("Window: built-in dock parts")
struct DockPartsAppTests {
    static let rootHub = "usb:00200000:8087:5787"
    static let realtekHub = "usb:00210000:0bda:0483"

    static func snapshot(_ fixture: String = "AnkerPrimeTB5") throws -> HostSnapshot {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../BusStopCoreTests/Fixtures/\(fixture).json").standardizedFileURL
        return TopologyBuilder.build(try Exporter.decodeRaw(Data(contentsOf: url)))
    }

    static func dock(_ snapshot: HostSnapshot) throws -> DeviceNode {
        try #require(snapshot.ports.flatMap(\.devices).first { $0.kind == .dock })
    }

    @Test func cablesListHasNoLinkToABuiltInPart() throws {
        let snapshot = try Self.snapshot()
        let port = try #require(snapshot.ports.first { !$0.devices.isEmpty })
        let cables = SidebarCable.cables(below: port.devices, from: port.label.title)
        let dock = try Self.dock(snapshot)
        #expect(!cables.contains { $0.childName == "USB3 HUB" })
        #expect(!cables.contains { $0.childName.hasPrefix("Anker") })
        #expect(cables.filter { $0.parentName == dock.name }.map(\.childName)
                == ["4-Port USB 3.0 Hub", "billboard", "Dell U4924DW", "Gigabyte M32U", "USB 10_100 LAN",
                    "USB Storage", "USB3.1 Hub"])
    }

    @Test func linkPageNamesTheDockAndTheBuiltInHub() throws {
        let snapshot = try Self.snapshot()
        let ends = try #require(LinkEnds.resolve(.device(Self.realtekHub), in: snapshot))
        guard case .device(let parent) = ends.parent else {
            Issue.record("The parent is not a device")
            return
        }
        #expect(parent.id == (try Self.dock(snapshot)).id)
        #expect(ends.builtInPart?.id == Self.rootHub)
        #expect(LinkEnds.resolve(.device(Self.rootHub), in: snapshot) == nil)
    }

    @Test func searchFindsTheDockByAPartName() throws {
        let dock = try Self.dock(Self.snapshot())
        #expect(TopologySearch.device(dock, matches: "USB3 HUB"))
        #expect(TopologySearch.device(dock, matches: "Intel"))
        #expect(!TopologySearch.device(dock, matches: "Keychron"))
        #expect(TopologySearch.prune(dock, query: "USB3 HUB")?.id == dock.id)
        // The card reader on the dock's captive hub is a device of its own, found by its name.
        let storage = try #require(dock.children.first { $0.name == "USB Storage" })
        #expect(TopologySearch.device(storage, matches: "USB Storage"))
    }

    @Test func textMentionsBuiltInPartsOnlyWhereItShould() throws {
        let snapshot = try Self.snapshot()
        let dock = try Self.dock(snapshot)
        #expect(WindowText.deviceAccessibility(dock, portTitle: "Left Center · USB-C").contains("5 built-in parts"))
        // The card and the list row count drawn devices only.
        #expect(WindowText.deviceSubtitle(dock) == "Dock · 19 devices · 22 W")
        #expect(WindowText.summary(snapshot).hasPrefix("6 ports · 20 devices"))
        #expect(WindowText.devicesSubtitle(snapshot)
                == "20 devices on every port and hub, not counting parts built into a dock or hub")
        let hub = try #require(dock.internalParts?.first { $0.id == Self.rootHub })
        #expect(WindowText.partDetail(hub).hasPrefix("Intel Corporation · 10 Gb/s"))
        // The two built-in "USB3.1 Hub" rows differ by location ID; other rows show none.
        let parts = try #require(dock.internalParts)
        let viaHubs = parts.filter { $0.name == "USB3.1 Hub" }.map { WindowText.partDetail($0, siblings: parts) }
        #expect(viaHubs.count == 2)
        #expect(Set(viaHubs).count == 2)
        #expect(viaHubs.allSatisfy { $0.contains("0x0024") })
        #expect(!WindowText.partDetail(hub, siblings: parts).contains("0x"))
    }

    /// A Thunderbolt display's parts (the Dell U4025QW capture) are named
    /// as built into the display, a dock's as built into the dock, and a
    /// hub's chips as built into the hub.
    @Test func partsAreNamedAfterWhatTheyAreBuiltInto() throws {
        let snapshot = try Self.snapshot("DellU4025QW")
        let monitor = try #require(snapshot.ports.flatMap(\.devices).first { $0.internalParts != nil })
        #expect(monitor.kind == .display)
        #expect(WindowText.builtInHost(monitor) == "display")
        #expect(WindowText.devicesSubtitle(snapshot).hasSuffix(", not counting parts built into a display or hub"))
        #expect(WindowText.builtInHost(try Self.dock(Self.snapshot())) == "dock")
        let hub = try #require(monitor.children.first { $0.internalParts != nil })
        #expect(WindowText.builtInHost(hub) == "hub")
    }

    /// A built-in part's link change points at the dock, but must not
    /// replace the dock's own link change when notifications settle.
    @Test func partLinkChangeKeepsTheDocksOwnNotification() throws {
        let before = try Self.snapshot()
        var after = before
        let portIndex = try #require(after.ports.firstIndex { !$0.devices.isEmpty })
        let dockIndex = try #require(after.ports[portIndex].devices.firstIndex { $0.kind == .dock })
        var dock = after.ports[portIndex].devices[dockIndex]
        var link = try #require(dock.link)
        link.bitsPerSecond = (link.bitsPerSecond ?? 0) / 2
        link.isAsymmetric = false
        dock.link = link
        var parts = dock.internalParts ?? []
        let hubIndex = try #require(parts.firstIndex { $0.id == Self.rootHub })
        parts[hubIndex].link?.bitsPerSecond = 5_000_000_000
        dock.internalParts = parts
        after.ports[portIndex].devices[dockIndex] = dock
        after.capturedAt = before.capturedAt.addingTimeInterval(2)

        let events = SnapshotDiffer.events(from: before, to: after, at: after.capturedAt)
        #expect(events.filter { $0.kind == .linkChanged }.map(\.deviceID) == [dock.id, dock.id])
        let text = NotificationManager.makeNotifications(for: events).map { "\($0.title) \($0.body)" }
            .joined(separator: "\n")
        // Both downgrades survive: the dock's Thunderbolt link and the hub's.
        #expect(text.contains("TB5 @ 40 Gb/s"), "\(text)")
        #expect(text.contains("Gen 2 @ 5 Gb/s"), "\(text)")
    }

    @Test func selectionOfAPartMovesToTheDock() throws {
        let snapshot = try Self.snapshot()
        let dock = try Self.dock(snapshot)
        #expect(PortStore.fallback(for: .device(Self.rootHub), in: snapshot) == .device(dock.id))
        #expect(PortStore.fallback(for: .link(.device(Self.rootHub)), in: snapshot) == .device(dock.id))
        // Any other device that left stays selected; the inspector says it is disconnected.
        #expect(PortStore.fallback(for: .device("usb:gone"), in: snapshot) == .device("usb:gone"))
        #expect(PortStore.fallback(for: .link(.device("usb:gone")), in: snapshot) == .link(.device("usb:gone")))
        #expect(PortStore.fallback(for: .port(PortKey(type: PortKey.usbCType, number: 99)), in: snapshot) == .host)
    }
}
