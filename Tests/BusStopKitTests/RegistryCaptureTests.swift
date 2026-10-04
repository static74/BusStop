import BusStopCore
import Foundation
import Testing
@testable import BusStopKit

@Suite("RegistryCapture")
struct RegistryCaptureTests {
    @Test func machineInfoHasModelAndVersion() {
        let machine = RegistryCapture.machineInfo()
        #expect(!machine.model.isEmpty)
        #expect(!machine.osVersion.isEmpty)
        #expect(machine.osVersion.split(separator: ".").count >= 2)
    }

    @Test func captureEncodesToJSON() throws {
        let raw = RegistryCapture.capture()
        #expect(!raw.machine.model.isEmpty)
        #expect(!raw.machine.osVersion.isEmpty)
        #expect(raw.schemaVersion == RawSnapshot.currentSchemaVersion)

        let data = try JSONEncoder().encode(raw)
        #expect(!data.isEmpty)
        let decoded = try JSONDecoder().decode(RawSnapshot.self, from: data)
        #expect(decoded.portNodes.count == raw.portNodes.count)
        #expect(decoded.usbDevices.count == raw.usbDevices.count)
        #expect(decoded.thunderboltSwitches.count == raw.thunderboltSwitches.count)
        #expect(decoded.displays.count == raw.displays.count)

        // Registry IDs are unique and parents point at captured nodes.
        let ids = raw.portNodes.map(\.id)
        #expect(Set(ids).count == ids.count)
        let idSet = Set(ids)
        for node in raw.portNodes {
            if let parent = node.parentID { #expect(idSet.contains(parent)) }
            #expect(!node.className.isEmpty)
            #expect(node.classChain.first == node.className)
            #expect(node.properties.keys.allSatisfy { !RegistryKeys.isNoise($0) })
        }
        let usbIDs = Set(raw.usbDevices.map(\.id))
        for device in raw.usbDevices {
            if let parent = device.parentDeviceID { #expect(usbIDs.contains(parent)) }
        }
    }

    @Test func concurrentCapturesAreSafe() async {
        let counts = await withTaskGroup(of: [Int].self) { group in
            for _ in 0..<4 {
                group.addTask {
                    let raw = RegistryCapture.capture()
                    return [raw.portNodes.count, raw.usbDevices.count, raw.displays.count]
                }
            }
            var results: [[Int]] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(counts.count == 4)
        #expect(Set(counts).count == 1)
    }

    @Test func captureWithoutSMC() {
        let raw = RegistryCapture.capture(includeSMC: false)
        #expect(raw.smcChannels.isEmpty)
        #expect(!raw.captureNotes.contains { $0.hasPrefix("SMC") })
    }

    @Test func registryHelpers() throws {
        let root = try #require(RegistryEntry.root())
        #expect(root.entryID != nil)
        #expect(root.className?.isEmpty == false)
        #expect(!root.children(in: RegistryPlane.service).isEmpty)
        #expect(root.parent(in: RegistryPlane.service) == nil)

        let chain = ClassHierarchy.chain(for: "IOService")
        #expect(chain.first == "IOService")
        #expect(chain.contains("IORegistryEntry"))
        #expect(ClassHierarchy.chain(for: "IOService") == chain)
        #expect(ClassHierarchy.chain(for: "NoSuchClassForBusStop") == ["NoSuchClassForBusStop"])

        #expect(RegistryEntry.matching(className: "NoSuchClassForBusStop").isEmpty)
        #expect(RegistryEntry(adopting: 0) == nil)
    }

    @Test func nodeFamilies() {
        #expect(PortNodeReader.family(of: ["AppleHPMInterfaceType10", "AppleHPMInterface", "AppleTCController",
                                           "IOAccessoryManagerUSBC", "IOAccessoryManager", "IOPort", "IOService"])
                == .controller)
        #expect(PortNodeReader.family(of: ["IOPort", "IOService"]) == .controller)
        #expect(PortNodeReader.family(of: ["IOPortTransportStateCC", "IOPortTransportState", "IOService"])
                == .transportCC)
        #expect(PortNodeReader.family(of: ["IOPortTransportStateUSB3"]) == .transportUSB)
        #expect(PortNodeReader.family(of: ["IOPortTransportStateDisplayPort"]) == .transportDisplayPort)
        #expect(PortNodeReader.family(of: ["IOPortTransportStateCIO"]) == .transportCIO)
        #expect(PortNodeReader.family(of: ["IOPortFeaturePowerSource"]) == .feature)
        #expect(PortNodeReader.family(of: ["AppleHPMLDCMType2"]) == .feature)
        #expect(PortNodeReader.family(of: ["IOPortTransportComponentCCUSBPDSOPp"]) == .component)
        #expect(PortNodeReader.family(of: ["IOPortTransportProtocolAppleUVDM"]) == .transportProtocol)
        #expect(PortNodeReader.family(of: ["SomethingNew", "IOService"]) == .other)
    }

    @Test func displayNameMatching() {
        let products = [
            DisplayReader.FramebufferProduct(name: "Studio Display", productID: 0x1114, vendorID: 0x610,
                                             serialNumber: 1),
            DisplayReader.FramebufferProduct(name: "Color LCD", productID: 0xA050, vendorID: nil, serialNumber: nil),
        ]
        #expect(DisplayReader.name(vendor: 0x610, model: 0x1114, serial: 0, in: products) == "Studio Display")
        #expect(DisplayReader.name(vendor: 0x610, model: 0xA050, serial: 0, in: products) == "Color LCD")
        #expect(DisplayReader.name(vendor: 0x10AC, model: 0x1114, serial: 0, in: products) == nil)
        #expect(DisplayReader.name(vendor: 0x610, model: 0x9999, serial: 0, in: products) == nil)
    }

    /// Prints what the machine running the tests exposes, so CI logs show the
    /// runner's capture.
    @Test func printCaptureForCILog() throws {
        let raw = RegistryCapture.capture()
        let classes = Dictionary(grouping: raw.portNodes, by: \.className).mapValues(\.count)
        print("""
        BUSSTOP-CAPTURE-SUMMARY \
        model=\(raw.machine.model) target=\(raw.machine.targetType ?? "-") chip=\(raw.machine.chip ?? "-") \
        os=\(raw.machine.osVersion) build=\(raw.machine.osBuild ?? "-") battery=\(raw.machine.hasBattery) \
        portNodes=\(raw.portNodes.count) controllerUUIDs=\(raw.portControllerUUIDs.count) \
        usbDevices=\(raw.usbDevices.count) tbSwitches=\(raw.thunderboltSwitches.count) \
        batteryService=\(raw.battery != nil) adapter=\(raw.adapter != nil) smcChannels=\(raw.smcChannels.count) \
        displays=\(raw.displays.count) notes=\(raw.captureNotes) \
        powerSourceMechanism=\(LiveMonitor.powerSourceMechanism)
        """)
        print("BUSSTOP-CAPTURE-CLASSES \(classes.sorted { $0.key < $1.key })")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(raw), as: UTF8.self)
        let limit = 20_000
        print("BUSSTOP-CAPTURE-JSON (\(json.count) characters\(json.count > limit ? ", truncated" : ""))")
        print(String(json.prefix(limit)))
        #expect(!json.isEmpty)
    }
}
