import Foundation
import Testing
@testable import BusStopCore

@Suite("Topology: ports and transports")
struct PortTopologyTests {
    typealias F = TopologyFixtures

    @Test func magSafeAndUSBCShareNumberOne() throws {
        let raw = F.raw(ports: [
            F.port(id: 10, type: 17, number: 1, description: "MagSafe 3", connected: true, supported: ["CC"],
                   className: "AppleHPMInterfaceType11"),
            F.port(id: 11, number: 1),
            F.port(id: 12, number: 2),
        ])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.ports.count == 3)
        let magSafe = try #require(snapshot.port(PortKey(type: 17, number: 1)))
        let usbC = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        #expect(magSafe.kind == .magSafe)
        #expect(magSafe.label.connector == "MagSafe")
        #expect(usbC.label.connector == "USB-C")
        #expect(usbC.kind == .usbC)
        #expect(magSafe.isConnected)
        #expect(!usbC.isConnected)
        // Generic order: MagSafe first, then USB-C by number.
        #expect(snapshot.ports.map(\.key.description) == ["17/1", "2/1", "2/2"])
    }

    @Test func nonContiguousNumbers() throws {
        let raw = F.raw(ports: [F.port(id: 4, number: 4), F.port(id: 1, number: 1), F.port(id: 2, number: 2)],
                        usb: [F.usb(id: 100, name: "Flash Drive", location: 0x0310_0000, drd: 4)])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.ports.map(\.number) == [1, 2, 4])
        let port4 = try #require(snapshot.port(PortKey(type: 2, number: 4)))
        #expect(port4.label.title == "USB-C 4")
        #expect(port4.label.source == .generic)
        #expect(port4.registryName == "Port-USB-C@4")
        #expect(port4.devices.map(\.name) == ["Flash Drive"])
    }

    @Test func userNamesOverrideLabels() throws {
        let raw = F.raw(ports: [F.port(id: 1, number: 1), F.port(id: 2, number: 2)])
        let snapshot = TopologyBuilder.build(raw, options: BuildOptions(userPortNames: ["2/2": "Desk"]))
        let port = try #require(snapshot.port(PortKey(type: 2, number: 2)))
        #expect(port.label.source == .user)
        #expect(port.label.title == "Desk")
        #expect(snapshot.port(PortKey(type: 2, number: 1))?.label.source == .generic)
    }

    @Test func skipsVirtualInductiveAndFeatureNodes() {
        let raw = F.raw(ports: [
            F.port(id: 1, number: 1),
            F.port(id: 2, type: 14, number: 101, description: "Inductive", extra: ["BuiltIn": false]),
            F.port(id: 3, type: 2, number: 1, description: "Virtual", className: "AppleHPMAIDType1"),
            // A transport with port-like keys but a ParentPortType.
            F.transport(id: 4, parent: 1, kind: "USB2", portNumber: 1,
                        extra: ["PortTypeDescription": "USB-C", "PortNumber": 1]),
        ])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.ports.map(\.key.description) == ["2/1"])
    }

    @Test func duplicateNodesForOnePortAreMerged() throws {
        let thin = RawNode(id: 50, className: "IOPort", name: "Port-USB-C", location: "1",
                           properties: ["PortTypeDescription": "USB-C", "PortNumber": 1, "PortType": 2])
        let raw = F.raw(ports: [thin, F.port(id: 51, number: 1, connected: true, active: ["CC", "USB2"]),
                                F.transport(id: 52, parent: 50, kind: "USB2", portNumber: 1)])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.ports.count == 1)
        let port = try #require(snapshot.ports.first)
        // The richer node represents the port; transports under either node count.
        #expect(port.isConnected)
        #expect(port.activeTransports.map(\.kind) == [.usb2])
    }

    @Test func bareUSBAPortsWithoutPortType() throws {
        let usbA = RawNode(id: 7, className: "IOPort", name: "Port-USB-A", location: "1",
                           properties: ["PortTypeDescription": "USB-A", "PortNumber": 1,
                                        "IOPersonalityPublisher": "com.apple.iokit.IOAccessoryManager"])
        let odd = RawNode(id: 8, className: "IOPort", name: "Port-Mystery", location: "1",
                          properties: ["PortTypeDescription": "Mystery", "PortNumber": 1])
        let snapshot = TopologyBuilder.build(F.raw(ports: [usbA, odd], usb: [
            F.usb(id: 70, name: "Keyboard", location: 0x0510_0000, path: "IOService:/a/b/Port-USB-A@1"),
        ]))
        let port = try #require(snapshot.port(PortKey(type: PortKey.usbAType, number: 1)))
        #expect(port.kind == .usbA)
        #expect(port.registryName == "Port-USB-A@1")
        #expect(port.devices.map(\.name) == ["Keyboard"])
        #expect(snapshot.port(PortKey(type: PortKey.unknownType, number: 1))?.kind == .unknown)
    }

    @Test func transportsActiveIsAuthoritative() throws {
        let raw = F.raw(ports: [
            F.port(id: 1, number: 1, connected: true, active: ["CC", "USB2", "DisplayPort"],
                   extra: ["IOAccessoryUSBSuperSpeedActive": true]),
            // USB3 node says active but the port does not list it.
            F.transport(id: 2, parent: 1, kind: "USB3", portNumber: 1, extra: ["SuperSpeedSignaling": 2]),
            F.transport(id: 3, parent: 1, kind: "USB2", portNumber: 1, extra: ["DataRate": 3]),
            F.transport(id: 4, parent: 1, kind: "CC", portNumber: 1),
            // DisplayPort is listed but has no node: still active.
        ])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.activeTransports.map(\.kind) == [.displayPort, .usb2])
        #expect(port.activeTransports.allSatisfy { $0.isActive && !$0.isTunneled })
        #expect(port.supportedTransports == [.cio, .usb3, .displayPort, .usb2])
    }

    @Test func nodeActiveFlagWhenThePortHasNoList() throws {
        var port = F.port(id: 1, number: 1, connected: true)
        port.properties["TransportsActive"] = nil
        let raw = F.raw(ports: [
            port,
            F.transport(id: 2, parent: 1, kind: "USB3", portNumber: 1, extra: ["SuperSpeedSignaling": 1]),
            F.transport(id: 3, parent: 1, kind: "USB2", portNumber: 1, active: false),
        ])
        let result = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(result.activeTransports.map(\.kind) == [.usb3])
        #expect(result.link?.label == "USB 3.2 Gen 1 @ 5 Gb/s")
    }

    @Test func explicitlyInactiveNodeRemovesAListedKind() throws {
        let raw = F.raw(ports: [
            F.port(id: 1, number: 1, connected: true, active: ["CC", "USB3"]),
            F.transport(id: 2, parent: 1, kind: "USB3", portNumber: 1, active: false),
        ])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.activeTransports.isEmpty)
        #expect(port.isConnected)
    }

    @Test func tunnelledTransportsAreNotThePortsOwn() throws {
        let raw = F.raw(ports: [
            F.port(id: 1, number: 1, connected: true, active: ["CC", "CIO"]),
            F.transport(id: 2, parent: 1, kind: "CIO", portNumber: 1),
            // Tunnelled by flag, by path, and by its CIO parent.
            F.transport(id: 3, parent: 1, kind: "USB3", portNumber: 1, tunneled: true),
            F.transport(id: 4, parent: nil, kind: "DisplayPort", portNumber: 1, path: "Port-USB-C@1/CIO/DisplayPort@0"),
            F.transport(id: 5, parent: 2, kind: "USB2", portNumber: 1),
        ])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.activeTransports.map(\.kind) == [.cio])
    }

    @Test func fastestTransportIsThePortLink() throws {
        let raw = F.raw(ports: [
            F.port(id: 1, number: 1, connected: true, active: ["CC", "USB2", "USB3", "DisplayPort"]),
            F.transport(id: 2, parent: 1, kind: "USB3", portNumber: 1, extra: ["SuperSpeedSignaling": 2]),
            F.transport(id: 3, parent: 1, kind: "USB2", portNumber: 1, extra: ["DataRate": 3]),
            F.transport(id: 4, parent: 1, kind: "DisplayPort", portNumber: 1,
                        extra: ["LinkRate": 2, "LaneCount": 2, "ProductName": "Monitor"]),
        ])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.activeTransports.map(\.kind) == [.usb3, .displayPort, .usb2])
        // HBR × 2 = 5.4 Gb/s is slower than USB 3.2 Gen 2.
        #expect(port.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(port.activeTransports.first { $0.kind == .displayPort }?.productName == "Monitor")
    }

    @Test func transportsJoinByKeysAndDescriptionWithoutParent() throws {
        let byKeys = F.transport(id: 2, parent: nil, kind: "USB2", portNumber: 2)
        var byPath = F.transport(id: 3, parent: nil, kind: "USB3", portNumber: 2, path: "Port-USB-C@2/USB3")
        byPath.properties["ParentPortType"] = nil
        byPath.properties["ParentPortNumber"] = nil
        let raw = F.raw(ports: [F.port(id: 1, number: 2, connected: true, active: ["CC", "USB2", "USB3"]),
                                byKeys, byPath])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.activeTransports.map(\.kind) == [.usb3, .usb2])
    }

    @Test func cableFromTheEmarker() throws {
        // ID header: active cable (product type 4), vendor 0x05AC.
        let header: UInt32 = (4 << 27) | 0x05AC
        let product: UInt32 = 0x1234 << 16
        // Cable VDO: USB4 Gen 3, 5 A.
        let cable: UInt32 = 0b011 | (2 << 5)
        func le(_ v: UInt32) -> PlistValue {
            .data(Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]))
        }
        let marker = F.node(id: 5, parent: 2, className: "IOPortTransportComponentCCUSBPDSOPp", name: "SOP'",
                            properties: ["ParentPortType": 2, "ParentPortNumber": 1, "Specification Revision": 3,
                                         "Metadata": .dict(["Product Type Description": "Active Cable",
                                                            "VDOs": .array([le(header), le(0), le(product), le(cable)])])])
        let raw = F.raw(ports: [F.port(id: 1, number: 1, connected: true, extra: ["OpticalCable": false]),
                                F.transport(id: 2, parent: 1, kind: "CC", portNumber: 1), marker])
        let info = try #require(TopologyBuilder.build(raw).ports.first?.cable)
        #expect(info.typeDescription == "Active Cable")
        #expect(info.isActive == true)
        #expect(info.isOptical == false)
        #expect(info.vendorID == 0x05AC)
        #expect(info.productID == 0x1234)
        #expect(info.speedDescription == "USB4 Gen 3 (40 Gb/s)")
        #expect(info.currentRatingMilliamps == 5000)
        #expect(info.pdRevision == 3)
    }

    @Test func cableNeedsAConnectionAndEvidence() {
        let marker = F.node(id: 5, parent: 1, className: "IOPortTransportComponentCCUSBPDSOPp", name: "SOP'",
                            properties: ["ParentPortType": 2, "ParentPortNumber": 1])
        // Not connected: stale e-marker is ignored.
        let unplugged = TopologyBuilder.build(F.raw(ports: [F.port(id: 1, number: 1), marker]))
        #expect(unplugged.ports.first?.cable == nil)
        // Connected without an e-marker or flags: nothing to say.
        let bare = TopologyBuilder.build(F.raw(ports: [F.port(id: 1, number: 1, connected: true)]))
        #expect(bare.ports.first?.cable == nil)
        // Connected optical cable without an e-marker.
        let optical = TopologyBuilder.build(F.raw(ports: [F.port(id: 1, number: 1, connected: true,
                                                                 extra: ["OpticalCable": true])]))
        #expect(optical.ports.first?.cable?.isOptical == true)
        // E-marker with undecodable VDOs: fields stay nil.
        let garbage = F.node(id: 6, parent: 1, className: "IOPortTransportComponentCCUSBPDSOPp", name: "SOP'",
                             properties: ["Metadata": .dict(["VDOs": .array([.string("x"), .data(Data([1]))])])])
        let odd = TopologyBuilder.build(F.raw(ports: [F.port(id: 1, number: 1, connected: true), garbage]))
        let cable = odd.ports.first?.cable
        #expect(cable != nil)
        #expect(cable?.speedDescription == nil)
        #expect(cable?.vendorID == nil)
    }

    @Test func subclassesAreRecognisedThroughTheClassChain() throws {
        // A driver subclass without TransportTypeDescription, a subclassed
        // e-marker with IDs as plain numbers, and a subclassed LDCM feature.
        let transport = RawNode(id: 2, parentID: 1, className: "AppleHPMTransportUSB3",
                                classChain: ["AppleHPMTransportUSB3", "IOPortTransportStateUSB3", "IOPortTransportState"],
                                name: "USB3", properties: ["Active": true, "SuperSpeedSignaling": 2])
        let marker = RawNode(id: 3, parentID: 1, className: "AppleHPMCableMarker",
                             classChain: ["AppleHPMCableMarker", "IOPortTransportComponentCCUSBPDSOPp"],
                             name: "SOP'", properties: ["Vendor ID": 0x2B89, "Product ID": .data(Data([0x12, 0x34])),
                                                        "Product Type Description": "Passive Cable"])
        let ldcm = RawNode(id: 4, parentID: 1, className: "AppleHPMLiquidSensor",
                           classChain: ["AppleHPMLiquidSensor", "AppleHPMLDCMType9"], name: "LDCM",
                           properties: ["LiquidDetected": true])
        let raw = F.raw(ports: [F.port(id: 1, number: 1, connected: true, active: ["CC", "USB3"]), transport, marker, ldcm])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.activeTransports.map(\.kind) == [.usb3])
        #expect(port.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(port.cable?.vendorID == 0x2B89)
        #expect(port.cable?.productID == nil)
        #expect(port.cable?.isActive == false)
        #expect(port.liquidDetected)
    }

    @Test func liquidDetection() {
        let byPortKey = TopologyBuilder.build(F.raw(ports: [
            F.port(id: 1, number: 1, extra: ["LDCM_LiquidDetected": true]), F.port(id: 2, number: 2),
        ]))
        #expect(byPortKey.ports.map(\.liquidDetected) == [true, false])

        let byFeature = TopologyBuilder.build(F.raw(ports: [
            F.port(id: 1, number: 1), F.port(id: 2, number: 2),
            F.node(id: 3, parent: 2, className: "AppleHPMLDCMType2", name: "LDCM",
                   properties: ["ParentPortType": 2, "ParentPortNumber": 2, "LiquidDetected": true]),
        ]))
        #expect(byFeature.ports.map(\.liquidDetected) == [false, true])
    }

    @Test func connectedWhenADeviceIsAttributedEvenWithoutConnectionActive() throws {
        let raw = F.raw(ports: [F.port(id: 1, number: 1)],
                        usb: [F.usb(id: 9, name: "Drive", location: 0x0110_0000, path: "x/Port-USB-C@1")])
        let port = try #require(TopologyBuilder.build(raw).ports.first)
        #expect(port.isConnected)
        #expect(port.deviceCount == 1)
    }

    @Test func noPortsAddsANoteAndKeepsDevices() {
        let raw = F.raw(usb: [F.usb(id: 1, name: "Keyboard", location: 0x0110_0000, path: "x/Port-USB-C@1",
                                    interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1,
                                                                 interfaceProtocol: 1)])],
                        notes: ["SMC unavailable"])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.ports.isEmpty)
        #expect(snapshot.otherDevices.map(\.name) == ["Keyboard"])
        #expect(snapshot.otherDevices.first?.kind == .keyboard)
        #expect(snapshot.captureNotes == ["SMC unavailable", TopologyBuilder.noPortDetailNote])
        #expect(TopologyBuilder.noPortDetailNote == "Port controller details are not available on this Mac.")
    }

    @Test func machineNameHeuristic() {
        #expect(TopologyBuilder.heuristicMachineName("MacBookPro99,1") == "MacBook Pro")
        #expect(TopologyBuilder.heuristicMachineName("MacBookAir99,2") == "MacBook Air")
        #expect(TopologyBuilder.heuristicMachineName("Macmini99,1") == "Mac mini")
        #expect(TopologyBuilder.heuristicMachineName("iMac99,1") == "iMac")
        #expect(TopologyBuilder.heuristicMachineName("MacPro99,1") == "Mac Pro")
        #expect(TopologyBuilder.heuristicMachineName("Mac99,1") == "Mac (Mac99,1)")
        #expect(TopologyBuilder.heuristicMachineName("") == "Mac")
        let snapshot = TopologyBuilder.build(F.raw(model: "MacBookPro99,1", hasBattery: false))
        #expect(snapshot.machine.name == "MacBook Pro")
        #expect(!snapshot.machine.isLaptop)
        #expect(snapshot.machine.isAppleSilicon)
    }
}
