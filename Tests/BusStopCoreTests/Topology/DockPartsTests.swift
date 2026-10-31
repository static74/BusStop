import Foundation
import Testing
@testable import BusStopCore

/// The rules that fold a Thunderbolt dock's built-in USB parts into the dock
/// (SPEC §5.4 "Built-in dock parts"), on small hand-made captures: a USB-C
/// port with a dock at depth 1 whose USB adapter carries a live tunnel, and
/// a USB 3 root hub on the Mac's own controller marked `UsbTunnel`.
@Suite("Topology: built-in dock parts")
struct DockPartsTests {
    typealias F = TopologyFixtures

    static let dockVendor = 0x291A
    static let dockModel = 0x83B5

    static func dockSwitch(id: UInt64 = 1100, parent: UInt64 = 1000, vendorID: Int? = dockVendor,
                           modelID: Int? = dockModel, liveUSB: Bool = true, upstreamLane: UInt64 = 1001,
                           model: String = "Prime Docking Station") -> RawThunderboltSwitch {
        F.tbSwitch(id: id, parent: parent, depth: parent == 1000 ? 1 : 2, uid: Int64(id) << 8, vendor: "Anker",
                   model: model, vendorID: vendorID, modelID: modelID, upstreamPort: 1,
                   ports: [F.lane(id: id + 1, portNumber: 1, speed: 0x2, width: 0x2),
                           F.lane(id: id + 2, portNumber: 3, speed: 0x2, width: 0x2),
                           F.adapter(id: id + 3, portNumber: 12, description: "USB Adapter", hops: liveUSB)],
                   ancestry: [RawAncestor(id: upstreamLane, className: "IOThunderboltPort", name: "IOThunderboltPort")]
                       + F.hostAncestry(acio: 0))
    }

    static func raw(usb: [RawUSBDevice], dock: RawThunderboltSwitch = dockSwitch(),
                    extraSwitches: [RawThunderboltSwitch] = []) -> RawSnapshot {
        let host = F.tbSwitch(id: 1000, depth: 0, uid: 0x05AC_0000_0000_1000,
                              ports: [F.lane(id: 1001, portNumber: 1, socket: "1", speed: 0x2, width: 0x2)],
                              ancestry: F.hostAncestry(acio: 0))
        return F.raw(ports: [F.port(id: 1, number: 1, connected: true, active: ["CC", "CIO"]),
                             F.transport(id: 11, parent: 1, kind: "CIO", portNumber: 1)],
                     usb: usb, thunderbolt: [host, dock] + extraSwitches)
    }

    /// The dock's USB 3 root hub: on the Mac's own controller, tunnelled.
    static func rootHub(id: UInt64 = 10, tunnel: Bool = true,
                        ancestry: [RawAncestor] = F.nativeAncestry(drd: 0)) -> RawUSBDevice {
        F.usb(id: id, name: "USB3 HUB", vendor: 0x8087, product: 0x5787, location: 0x0020_0000 + UInt32(id - 10),
              speed: 10_000_000_000, deviceClass: 9, bcdUSB: 0x0320, path: "a/Port-USB-C@1", ancestry: ancestry,
              extra: tunnel ? ["UsbTunnel": true] : [:])
    }

    /// A device below `parent` on a port whose `USBPortType` is `portType`
    /// (1 = captive, 0 = standard).
    static func device(_ id: UInt64, parent: UInt64, name: String, vendor: Int = 0x1234, product: Int = 0x5678,
                       hub: Bool = false, deviceClass: Int? = nil, portType: Int = 0,
                       interfaces: [RawUSBInterface] = []) -> RawUSBDevice {
        F.usb(id: id, parent: parent, name: name, vendor: vendor, product: product, location: UInt32(id) << 12,
              deviceClass: deviceClass ?? (hub ? 9 : 0), ancestry: F.nativeAncestry(drd: 0), interfaces: interfaces,
              extra: ["USBPortType": .int(Int64(portType))])
    }

    static func identity(_ id: UInt64, parent: UInt64, portType: Int = 0) -> RawUSBDevice {
        device(id, parent: parent, name: "Anker Docking Station", vendor: dockVendor, product: dockModel,
               portType: portType, interfaces: [RawUSBInterface(interfaceClass: 0x11)])
    }

    static func dock(_ snapshot: HostSnapshot) throws -> DeviceNode {
        try #require(snapshot.port(PortKey(type: 2, number: 1))?.devices.first { $0.bus == .thunderbolt })
    }

    static func partNames(_ raw: RawSnapshot) throws -> [String] {
        try dock(TopologyBuilder.build(raw)).internalParts?.map(\.name) ?? []
    }

    static func childNames(_ raw: RawSnapshot) throws -> [String] {
        try dock(TopologyBuilder.build(raw)).children.map(\.name)
    }

    // MARK: - Rules A and B

    @Test func rootHubAndDockFunctionsFold() throws {
        let raw = Self.raw(usb: [Self.rootHub(), Self.identity(20, parent: 10),
                                 Self.device(21, parent: 10, name: "Drive")])
        let dock = try Self.dock(TopologyBuilder.build(raw))
        #expect(dock.kind == .dock)
        #expect(dock.internalParts?.map(\.name) == ["Anker Docking Station", "USB3 HUB"])
        #expect(dock.children.map(\.name) == ["Drive"])
        #expect(dock.children.first?.internalParentID == dock.internalParts?.last?.id)
        #expect(dock.descendantCount == 1)
    }

    @Test func noTunnelledRootFoldsNothing() throws {
        let raw = Self.raw(usb: [Self.rootHub(tunnel: false), Self.identity(20, parent: 10)])
        #expect(try Self.partNames(raw).isEmpty)
        #expect(try Self.childNames(raw) == ["USB3 HUB"])
    }

    @Test func twoTunnelledRootsFoldNothing() throws {
        let raw = Self.raw(usb: [Self.rootHub(id: 10), Self.rootHub(id: 11), Self.identity(20, parent: 10)])
        #expect(try Self.partNames(raw).isEmpty)
    }

    /// A Thunderbolt 3 or 4 dock brings its own PCIe USB controller; its
    /// root hub is not the Mac's, and nothing folds.
    @Test func rootOnTheDocksOwnControllerFoldsNothing() throws {
        let raw = Self.raw(usb: [Self.rootHub(ancestry: F.tunnelAncestry(pcie: 0)), Self.identity(20, parent: 10)])
        #expect(try Self.partNames(raw).isEmpty)
    }

    /// Another hub with the same device ID as the root hub (same location,
    /// vendor and product) but no `UsbTunnel` stays on the map, whichever
    /// order the two come in.
    @Test(arguments: [UInt64(5), 15, 99])
    func hubWithTheRootsIDIsNotTakenForTheRoot(_ cloneID: UInt64) throws {
        var clone = F.usb(id: cloneID, name: "USB3 HUB", vendor: 0x8087, product: 0x5787, location: 0x0020_0000,
                          speed: 10_000_000_000, deviceClass: 9, bcdUSB: 0x0320, path: "a/Port-USB-C@1",
                          ancestry: F.nativeAncestry(drd: 0))
        clone.node.properties["USBPortType"] = 0
        let raw = Self.raw(usb: [Self.rootHub(), clone, Self.device(21, parent: cloneID, name: "Behind clone"),
                                 Self.device(22, parent: 10, name: "Behind root")])
        let dock = try Self.dock(TopologyBuilder.build(raw))
        #expect(dock.internalParts?.map(\.registryID) == [10])
        let clones = dock.children.filter { $0.registryID == cloneID }
        #expect(clones.count == 1)
        #expect(clones.first?.children.map(\.name) == ["Behind clone"])
        #expect(dock.children.contains { $0.name == "Behind root" })
        DockPartsInvariantTests.check(raw)
    }

    @Test func secondTunnelSwitchFoldsNothing() throws {
        let second = Self.dockSwitch(id: 1200, parent: 1100, vendorID: 0x1111, modelID: 0x2222,
                                     upstreamLane: 1102, model: "Other Dock")
        let raw = Self.raw(usb: [Self.rootHub(), Self.identity(20, parent: 10)], extraSwitches: [second])
        #expect(try Self.partNames(raw).isEmpty)
    }

    @Test func idleUSBTunnelFoldsNothing() throws {
        let raw = Self.raw(usb: [Self.rootHub(), Self.identity(20, parent: 10)],
                           dock: Self.dockSwitch(liveUSB: false))
        #expect(try Self.partNames(raw).isEmpty)
    }

    @Test func missingOrZeroIdentityTurnsOffRuleB() throws {
        for (vendor, model) in [(nil, Self.dockModel), (Self.dockVendor, 0), (0, 0)] as [(Int?, Int?)] {
            let raw = Self.raw(usb: [Self.rootHub(), Self.identity(20, parent: 10)],
                               dock: Self.dockSwitch(vendorID: vendor, modelID: model))
            #expect(try Self.partNames(raw) == ["USB3 HUB"])
            #expect(try Self.childNames(raw) == ["Anker Docking Station"])
        }
    }

    @Test func sharedIdentityTurnsOffRuleB() throws {
        let twin = F.tbSwitch(id: 5000, depth: 1, vendor: "Anker", model: "Prime Docking Station",
                              vendorID: Self.dockVendor, modelID: Self.dockModel)
        let raw = Self.raw(usb: [Self.rootHub(), Self.identity(20, parent: 10)], extraSwitches: [twin])
        #expect(try Self.partNames(raw) == ["USB3 HUB"])
    }

    // MARK: - Rules C and D

    /// The Anker shape: a hub holding the dock's identity on a captive port
    /// (D) and a captive hub below it (C). The dock's Ethernet and card
    /// reader on that hub are functions people use and stay on the map, as
    /// does an external hub on it with its subtree.
    @Test func identityHolderAndCaptiveHubFold() throws {
        let raw = Self.raw(usb: [
            Self.rootHub(),
            Self.device(30, parent: 10, name: "Holder Hub", hub: true),
            Self.identity(31, parent: 30, portType: 1),
            Self.device(32, parent: 30, name: "Captive Hub", hub: true, portType: 1),
            Self.device(33, parent: 32, name: "Ethernet", interfaces: [RawUSBInterface(interfaceClass: 2)]),
            Self.device(34, parent: 32, name: "Card Reader", interfaces: [RawUSBInterface(interfaceClass: 8)]),
            Self.device(35, parent: 32, name: "Desk Hub", hub: true),
            Self.device(36, parent: 35, name: "Keyboard"),
            Self.device(37, parent: 30, name: "Port Hub", hub: true),
            Self.device(38, parent: 37, name: "Phone"),
        ])
        let dock = try Self.dock(TopologyBuilder.build(raw))
        #expect(Set(dock.internalParts?.map(\.name) ?? []) == [
            "USB3 HUB", "Holder Hub", "Anker Docking Station", "Captive Hub",
        ])
        #expect(dock.children.map(\.name) == ["Card Reader", "Desk Hub", "Ethernet", "Port Hub"])
        #expect(dock.children.first { $0.name == "Desk Hub" }?.children.map(\.name) == ["Keyboard"])
        #expect(dock.children.last?.children.map(\.name) == ["Phone"])
    }

    @Test func captiveBillboardBelowAHolderFolds() throws {
        let raw = Self.raw(usb: [
            Self.rootHub(),
            Self.device(30, parent: 10, name: "Holder Hub", hub: true),
            Self.identity(31, parent: 30, portType: 1),
            Self.device(32, parent: 30, name: "Billboard", deviceClass: 0x11, portType: 1),
            Self.device(33, parent: 30, name: "Interface Billboard", portType: 1,
                        interfaces: [RawUSBInterface(interfaceClass: 0x11)]),
        ])
        #expect(Set(try Self.partNames(raw)) == ["USB3 HUB", "Holder Hub", "Anker Docking Station", "Billboard",
                                                "Interface Billboard"])
    }

    /// A captive function that is not a hub or billboard, on a hub folded
    /// for holding the identity, stays: only a captive hub's functions fold.
    @Test func captiveFunctionOnAHolderStays() throws {
        let raw = Self.raw(usb: [
            Self.rootHub(),
            Self.device(30, parent: 10, name: "Holder Hub", hub: true),
            Self.identity(31, parent: 30, portType: 1),
            Self.device(32, parent: 30, name: "Ethernet", portType: 1,
                        interfaces: [RawUSBInterface(interfaceClass: 2)]),
        ])
        #expect(try Self.childNames(raw) == ["Ethernet"])
    }

    /// The root hub's own ports report no captive flags that can be trusted:
    /// a captive-flagged hub straight on the root hub stays.
    @Test func captiveHubOnTheRootHubStays() throws {
        let raw = Self.raw(usb: [
            Self.rootHub(),
            Self.device(30, parent: 10, name: "Monitor Hub", hub: true, portType: 1),
            Self.device(31, parent: 30, name: "Webcam", portType: 1),
        ])
        #expect(try Self.partNames(raw) == ["USB3 HUB"])
        #expect(try Self.childNames(raw) == ["Monitor Hub"])
    }

    /// Behind an external hub nothing is the dock's; the captive hub there
    /// is a chip of the external hub instead (`HubChips`).
    @Test func captiveHubBelowAnExternalHubStays() throws {
        let raw = Self.raw(usb: [
            Self.rootHub(),
            Self.device(30, parent: 10, name: "Desk Hub", hub: true),
            Self.device(31, parent: 30, name: "Inner Hub", hub: true, portType: 1),
            Self.identity(32, parent: 31, portType: 1),
        ])
        #expect(try Self.partNames(raw) == ["USB3 HUB"])
        let dock = try Self.dock(TopologyBuilder.build(raw))
        #expect(dock.children.map(\.name) == ["Desk Hub"])
        #expect(dock.children.first?.internalParts?.map(\.name) == ["Inner Hub"])
        #expect(dock.descendantCount == 2)
    }

    /// The identity on a standard port does not make its hub built-in.
    @Test func identityOnAStandardPortLeavesTheHub() throws {
        let raw = Self.raw(usb: [
            Self.rootHub(),
            Self.device(30, parent: 10, name: "Some Hub", hub: true),
            Self.identity(31, parent: 30, portType: 0),
        ])
        #expect(try Self.partNames(raw) == ["USB3 HUB"])
        #expect(try Self.childNames(raw) == ["Some Hub"])
    }

    /// Two hubs that both hold the identity on a captive port cannot both be
    /// the dock's: the identity rules turn off.
    @Test func twoIdentityHoldersTurnOffTheIdentityRules() throws {
        let raw = Self.raw(usb: [
            Self.rootHub(),
            Self.identity(20, parent: 10),
            Self.device(30, parent: 10, name: "Hub A", hub: true),
            Self.identity(31, parent: 30, portType: 1),
            Self.device(40, parent: 10, name: "Hub B", hub: true),
            Self.identity(41, parent: 40, portType: 1),
        ])
        #expect(try Self.partNames(raw) == ["USB3 HUB"])
        #expect(try Self.childNames(raw) == ["Anker Docking Station", "Hub A", "Hub B"])
    }

    @Test func thunderboltDevicesBelowTheDockStay() throws {
        let display = F.tbSwitch(id: 1200, parent: 1100, depth: 2, uid: 0x1200, vendor: "Apple Inc.",
                                 model: "Studio Display", upstreamPort: 1,
                                 ports: [F.lane(id: 1201, portNumber: 1, speed: 0x2, width: 0x2),
                                         F.adapter(id: 1202, portNumber: 10, description: "DP or HDMI Adapter",
                                                   hops: true)],
                                 ancestry: [RawAncestor(id: 1102, className: "IOThunderboltPort",
                                                        name: "IOThunderboltPort")] + F.hostAncestry(acio: 0))
        let raw = Self.raw(usb: [Self.rootHub(), Self.identity(20, parent: 10)], extraSwitches: [display])
        let dock = try Self.dock(TopologyBuilder.build(raw))
        #expect(dock.internalParts?.map(\.name) == ["Anker Docking Station", "USB3 HUB"])
        #expect(dock.children.map(\.name) == ["Studio Display"])
        #expect(dock.children.first?.kind == .display)
    }

    // MARK: - Rule F (container IDs)

    static let product = "6A1F0E43-9B2C-4D8A-8E2F-1C3B5D7E9F00"
    static let other = "0B4F1A3C-77D2-4E19-9F0A-2C6E8B1D5A47"

    /// A Thunderbolt display with a live USB tunnel.
    static func display() -> RawThunderboltSwitch { dockSwitch(model: "Studio Monitor") }

    /// `device` reporting `container` as its `kUSBContainerID`.
    static func contained(_ device: RawUSBDevice, _ container: String) -> RawUSBDevice {
        var device = device
        device.node.properties["kUSBContainerID"] = .string(container)
        return device
    }

    /// A monitor's hub chips and Ethernet sharing the root hub's container
    /// ID, a webcam of another product and a keyboard with none on its ports.
    static func containerRaw(dock: RawThunderboltSwitch) -> RawSnapshot {
        raw(usb: [
            contained(rootHub(), product),
            contained(device(30, parent: 10, name: "Monitor Hub", hub: true), product),
            contained(device(31, parent: 30, name: "Port Hub", hub: true, portType: 1), product),
            contained(device(32, parent: 30, name: "Ethernet", portType: 1,
                             interfaces: [RawUSBInterface(interfaceClass: 2)]), product),
            contained(device(40, parent: 31, name: "Webcam"), other),
            device(41, parent: 31, name: "Keyboard"),
        ], dock: dock)
    }

    /// Docks and displays alike: a device sharing the root hub's container ID
    /// is part of the same product, wherever it sits below the root hub.
    @Test(arguments: [true, false])
    func devicesSharingTheRootHubsContainerFold(_ isDisplay: Bool) throws {
        let raw = Self.containerRaw(dock: isDisplay ? Self.display() : Self.dockSwitch())
        let dock = try Self.dock(TopologyBuilder.build(raw))
        let kind: DeviceKind = isDisplay ? .display : .dock
        #expect(dock.kind == kind)
        #expect(dock.internalParts?.map(\.name) == ["Ethernet", "Monitor Hub", "Port Hub", "USB3 HUB"])
        #expect(dock.children.map(\.name) == ["Keyboard", "Webcam"])
        let portHub = dock.internalParts?.first { $0.name == "Port Hub" }
        #expect(dock.children.allSatisfy { $0.internalParentID == portHub?.id })
        DockPartsInvariantTests.check(raw)
    }

    /// Rules work top-down: a device behind a hub of another product stays,
    /// whatever its container ID.
    @Test func sharedContainerBehindAnExternalHubStays() throws {
        let raw = Self.raw(usb: [
            Self.contained(Self.rootHub(), Self.product),
            Self.contained(Self.device(30, parent: 10, name: "Desk Hub", hub: true), Self.other),
            Self.contained(Self.device(31, parent: 30, name: "Behind Desk Hub"), Self.product),
        ], dock: Self.display())
        #expect(try Self.partNames(raw) == ["USB3 HUB"])
        let display = try Self.dock(TopologyBuilder.build(raw))
        #expect(display.children.map(\.name) == ["Desk Hub"])
        #expect(display.descendantCount == 2)
    }

    @Test func missingOrZeroContainerMatchesNothing() throws {
        let zero = "00000000-0000-0000-0000-000000000000"
        for (rootContainer, hubContainer) in [(zero, zero), (nil, Self.product)] as [(String?, String)] {
            let root = rootContainer.map { Self.contained(Self.rootHub(), $0) } ?? Self.rootHub()
            let hub = Self.contained(Self.device(30, parent: 10, name: "Monitor Hub", hub: true), hubContainer)
            let raw = Self.raw(usb: [root, hub], dock: Self.display())
            #expect(try Self.partNames(raw) == ["USB3 HUB"])
            #expect(try Self.childNames(raw) == ["Monitor Hub"])
        }
    }

    /// The same UUID in another case or without dashes still matches.
    @Test func containerIDsMatchWhateverTheirForm() throws {
        let undashed = Self.product.lowercased().filter { $0 != "-" }
        let raw = Self.raw(usb: [
            Self.contained(Self.rootHub(), Self.product),
            Self.contained(Self.device(30, parent: 10, name: "Monitor Hub", hub: true), undashed),
        ], dock: Self.display())
        #expect(try Self.partNames(raw) == ["Monitor Hub", "USB3 HUB"])
    }

    /// Redacted exports replace container IDs with stand-ins that keep which
    /// devices share one, so a redacted capture folds the same parts.
    @Test func redactedCaptureFoldsTheSameParts() throws {
        let raw = Self.containerRaw(dock: Self.display())
        let redacted = Exporter.redacted(raw)
        let containers = Dictionary(uniqueKeysWithValues: redacted.usbDevices.map {
            ($0.id, $0.node.properties.string("kUSBContainerID"))
        })
        #expect(containers[10] != Self.product)
        #expect(containers[10] == containers[30])
        #expect(containers[10] != containers[40])
        #expect(!redacted.usbDevices.contains { device in
            [Self.product, Self.other].contains { device.node.properties.string("kUSBContainerID") == $0 }
        })
        #expect(try Self.partNames(redacted) == Self.partNames(raw))
        #expect(try Self.childNames(redacted) == Self.childNames(raw))
    }

    // MARK: - Diagnostics and events

    /// The dock's root hub fell back to USB 2: one finding, on the dock card,
    /// and none for the USB 3 drive behind the hub.
    @Test func builtInHubAtUSB2SpeedIsOneFindingOnTheDock() throws {
        var hub = Self.rootHub()
        hub.node.properties["UsbLinkSpeed"] = .int(480_000_000)
        var drive = Self.device(21, parent: 10, name: "Drive")
        drive.node.properties["bcdUSB"] = .int(0x0320)
        let snapshot = TopologyBuilder.build(Self.raw(usb: [hub, drive]))
        let dock = try Self.dock(snapshot)
        let findings = snapshot.diagnostics.filter { $0.kind == .usb2Fallback }
        #expect(findings.count == 1)
        #expect(findings.first?.deviceID == dock.id)
        #expect(findings.first?.title == "USB3 HUB is running at USB 2 speed")
        #expect(findings.first?.detail.contains("built into Prime Docking Station") == true)
    }

    @Test func builtInHubLinkChangeNamesTheDock() throws {
        let before = TopologyBuilder.build(Self.raw(usb: [Self.rootHub()]))
        var slow = Self.rootHub()
        slow.node.properties["UsbLinkSpeed"] = .int(5_000_000_000)
        let after = TopologyBuilder.build(Self.raw(usb: [slow]))
        let events = SnapshotDiffer.events(from: before, to: after, at: F.date.addingTimeInterval(2))
        let dock = try Self.dock(after)
        #expect(events.map(\.kind) == [.linkChanged])
        #expect(events.first?.title == "USB3 HUB slowed down")
        #expect(events.first?.deviceID == dock.id)
        #expect(events.first?.detail.contains("built into Prime Docking Station") == true)
    }

    // MARK: - Model

    @Test func unfoldedRestoresTheTree() throws {
        let raw = Self.raw(usb: [
            Self.rootHub(),
            Self.device(30, parent: 10, name: "Holder Hub", hub: true),
            Self.identity(31, parent: 30, portType: 1),
            Self.device(37, parent: 30, name: "Port Hub", hub: true),
            Self.device(38, parent: 37, name: "Phone"),
        ])
        let folded = try Self.dock(TopologyBuilder.build(raw))
        let unfolded = try Self.dock(TopologyBuilder.build(raw, options: BuildOptions(), foldsDockParts: false))
        #expect(TopologyBuilder.sortedTree([folded.unfolded()]) == [unfolded])
        #expect(unfolded.unfolded() == unfolded)
    }

    /// A part whose ID repeats a visible device's gets a new one, and what
    /// hangs off it follows.
    @Test func repeatedPartIDsAreMadeUnique() {
        var part = DeviceNode(id: "usb:x", registryID: 0xAB, bus: .usb, kind: .hub, name: "Hub")
        part.internalParentID = nil
        var moved = DeviceNode(id: "usb:y", bus: .usb, kind: .storage, name: "Drive")
        moved.internalParentID = "usb:x"
        let dock = DeviceNode(id: "tb:1", bus: .thunderbolt, kind: .dock, name: "Dock", children: [moved],
                              internalParts: [part])
        let other = DeviceNode(id: "usb:x", bus: .usb, kind: .other, name: "Other")
        var snapshot = HostSnapshot(capturedAt: F.date,
                                    machine: MachineSummary(model: "Mac", name: "Mac", osVersion: "", isLaptop: false),
                                    otherDevices: [other, dock])
        TopologyBuilder.makeDeviceIDsUnique(&snapshot)
        let fixed = snapshot.otherDevices[1]
        #expect(fixed.internalParts?.first?.id == "usb:x#ab")
        #expect(fixed.children.first?.internalParentID == "usb:x#ab")
    }

    /// A part's serial number is redacted wherever it appears: its own
    /// field, its raw properties, and IDs that contain it, including the
    /// `internalParentID` of what hangs off the part.
    @Test func redactionScrubsAPartsSerial() throws {
        let serial = "PART5ER1AL77"
        let partID = "usb:\(serial):8087:5787"
        let part = DeviceNode(id: partID, registryID: 10, bus: .usb, kind: .hub, name: "USB3 HUB",
                              serialNumber: serial,
                              properties: ["USB Serial Number": .string(serial),
                                           "kUSBSerialNumberString": .string(serial), "idVendor": 0x8087])
        var moved = DeviceNode(id: "usb:00210000:0bda:0483", bus: .usb, kind: .hub, name: "Desk Hub")
        moved.internalParentID = partID
        let dock = DeviceNode(id: "tb:1", bus: .thunderbolt, kind: .dock, name: "Dock", children: [moved],
                              internalParts: [part])
        let snapshot = HostSnapshot(capturedAt: F.date,
                                    machine: MachineSummary(model: "Mac", name: "Mac", osVersion: "", isLaptop: false),
                                    otherDevices: [dock])
        #expect(String(decoding: try Exporter.json(snapshot, redact: false), as: UTF8.self).contains(serial))
        let text = String(decoding: try Exporter.json(snapshot), as: UTF8.self)
        #expect(!text.contains(serial), "\(text)")

        let redacted = Exporter.redacted(snapshot).otherDevices[0]
        let redactedPart = try #require(redacted.internalParts?.first)
        #expect(redactedPart.serialNumber == Exporter.redactedText)
        #expect(redactedPart.properties?.string("USB Serial Number") == Exporter.redactedText)
        #expect(redactedPart.id == "usb:\(Exporter.redactedText):8087:5787")
        #expect(redacted.children.first?.internalParentID == redactedPart.id)
    }

    /// Hand-edited JSON can make parts point at each other in a loop.
    @Test func unfoldingACycleNeverHangs() {
        var a = DeviceNode(id: "a", bus: .usb, kind: .hub, name: "A")
        var b = DeviceNode(id: "b", bus: .usb, kind: .hub, name: "B")
        a.internalParentID = "b"
        b.internalParentID = "a"
        var child = DeviceNode(id: "c", bus: .usb, kind: .other, name: "C",
                               power: DevicePower(allocatedMilliwatts: 500))
        child.internalParentID = "a"
        let dock = DeviceNode(id: "dock", bus: .thunderbolt, kind: .dock, name: "Dock", children: [child],
                              internalParts: [a, b, a])
        // The loop's members go directly under the dock, and nothing is lost.
        let restored = dock.unfolded()
        #expect(restored.children.map(\.id).sorted() == ["a", "a", "b"])
        #expect(restored.flattened().map(\.device.id).sorted() == ["a", "a", "b", "c", "dock"])
        #expect(restored.children.first { $0.id == "a" }?.children.map(\.id) == ["c"])
        #expect(dock.rolledUpMilliwatts == 500)
        #expect(dock.rolledUpMilliwatts == restored.rolledUpMilliwatts)
        #expect(dock.downstreamMilliwatts == restored.downstreamMilliwatts)
        #expect(dock.descendantCount == 1)
    }

    /// A self-powered built-in hub still stops the roll-up for what hangs
    /// below it, as it did before the hub was folded.
    @Test func selfPoweredPartsStopTheRollUp() {
        var hub = DeviceNode(id: "hub", bus: .usb, kind: .hub, name: "Hub",
                             power: DevicePower(allocatedMilliwatts: 100, isSelfPowered: true))
        hub.internalParentID = nil
        var drive = DeviceNode(id: "drive", bus: .usb, kind: .storage, name: "Drive",
                               power: DevicePower(allocatedMilliwatts: 4_500))
        drive.internalParentID = "hub"
        let ssd = DeviceNode(id: "ssd", bus: .usb, kind: .storage, name: "SSD",
                             power: DevicePower(allocatedMilliwatts: 900))
        let dock = DeviceNode(id: "dock", bus: .thunderbolt, kind: .dock, name: "Dock", children: [drive, ssd],
                              internalParts: [hub])
        #expect(dock.rolledUpMilliwatts == 1_000)
        #expect(dock.downstreamMilliwatts == 5_500)

        // A part below the self-powered hub, with a device of its own.
        var inner = DeviceNode(id: "inner", bus: .usb, kind: .hub, name: "Inner",
                               power: DevicePower(allocatedMilliwatts: 200))
        inner.internalParentID = "hub"
        var keyboard = DeviceNode(id: "kb", bus: .usb, kind: .keyboard, name: "Keyboard",
                                  power: DevicePower(allocatedMilliwatts: 300))
        keyboard.internalParentID = "inner"
        let deeper = DeviceNode(id: "dock", bus: .thunderbolt, kind: .dock, name: "Dock",
                                children: [drive, ssd, keyboard], internalParts: [inner, hub])
        #expect(deeper.rolledUpMilliwatts == 1_000)
        #expect(deeper.rolledUpMilliwatts == deeper.unfolded().rolledUpMilliwatts)
        #expect(deeper.downstreamMilliwatts == 6_000)
        #expect(deeper.downstreamMilliwatts == deeper.unfolded().downstreamMilliwatts)
    }
}
