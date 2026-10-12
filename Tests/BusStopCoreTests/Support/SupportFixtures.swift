import Foundation
@testable import BusStopCore

/// Hand-built snapshots for the label, diagnostics, event and export tests.
///
/// Everything lives in this namespace so the helpers cannot clash with other
/// test files in the module.
enum SupportFixtures {
    /// 2026-10-04T12:00:00Z, a whole second so ISO-8601 round trips are exact.
    static let date = Date(timeIntervalSince1970: 1_791_115_200)

    // MARK: Machine

    static func laptop(model: String = "Mac17,9", name: String = "MacBook Pro (14-inch, 2026, M5 Pro)") -> MachineSummary {
        MachineSummary(model: model, name: name, chip: "Apple M5 Pro", osVersion: "27.0", isLaptop: true)
    }

    static func desktop() -> MachineSummary {
        MachineSummary(model: "Mac16,11", name: "Mac mini (2024, M4 Pro)", chip: "Apple M4 Pro", osVersion: "27.0",
                       isLaptop: false)
    }

    // MARK: Links

    /// A USB link with the generation name for its rate.
    static func usbLink(_ bps: Int64) -> LinkInfo {
        let generation: String
        switch bps {
        case ..<13_000_000: generation = "USB 1.1"
        case ..<500_000_000: generation = "USB 2.0"
        case ..<6_000_000_000: generation = "USB 3.2 Gen 1"
        case ..<11_000_000_000: generation = "USB 3.2 Gen 2"
        default: generation = "USB 3.2 Gen 2x2"
        }
        return LinkInfo(family: .usb, generation: generation, bitsPerSecond: bps)
    }

    static func thunderboltLink(_ gbps: Int64) -> LinkInfo {
        LinkInfo(family: .thunderbolt, generation: "Thunderbolt / USB4", bitsPerSecond: gbps * 1_000_000_000, lanes: 2)
    }

    // MARK: Devices

    static func usbDevice(_ id: String, _ name: String, kind: DeviceKind = .storage, bps: Int64? = nil,
                          milliwatts: Int? = nil, usbVersion: String? = "3.2", serial: String? = nil,
                          selfPowered: Bool? = nil, children: [DeviceNode] = [],
                          properties: PropertyBag? = nil) -> DeviceNode {
        DeviceNode(id: id, bus: .usb, kind: kind, name: name, vendorID: 0x04e8, productID: 0x61fb,
                   serialNumber: serial, usbVersion: usbVersion, deviceClass: kind == .hub ? 9 : 0,
                   link: bps.map(usbLink), power: milliwatts.map {
                       DevicePower(allocatedMilliwatts: $0, source: .usbAllocation, isSelfPowered: selfPowered)
                   } ?? (selfPowered.map { DevicePower(allocatedMilliwatts: nil, isSelfPowered: $0) }),
                   children: children, properties: properties)
    }

    static func hub(_ id: String, _ name: String = "USB hub", bps: Int64 = 5_000_000_000, selfPowered: Bool? = false,
                    milliwatts: Int? = nil, children: [DeviceNode]) -> DeviceNode {
        usbDevice(id, name, kind: .hub, bps: bps, milliwatts: milliwatts, usbVersion: "3.2", selfPowered: selfPowered,
                  children: children)
    }

    // MARK: Ports

    static func label(_ location: String?, connector: String = "USB-C", number: Int) -> PortLabel {
        PortLabel(location: location, source: location == nil ? .generic : .catalog, connector: connector,
                  number: number)
    }

    static func usbC(_ number: Int, _ location: String?, supported: [TransportKind] = [.usb2, .usb3, .cio],
                     connected: Bool? = nil, link: LinkInfo? = nil, power: PortPower? = nil,
                     devices: [DeviceNode] = [], statistics: PortStatistics? = nil, liquid: Bool = false,
                     properties: PropertyBag? = nil) -> PhysicalPort {
        PhysicalPort(key: PortKey(type: PortKey.usbCType, number: number), kind: .usbC, number: number,
                     registryName: "Port-USB-C@\(number)", label: label(location, number: number),
                     supportedTransports: supported, isConnected: connected ?? !devices.isEmpty, link: link,
                     power: power, devices: devices, statistics: statistics, liquidDetected: liquid,
                     properties: properties)
    }

    static func magSafe(location: String = "Left Rear", charger: ChargerInfo? = nil, inputMilliwatts: Int? = nil) -> PhysicalPort {
        PhysicalPort(key: PortKey(type: PortKey.magSafeType, number: 1), kind: .magSafe, number: 1,
                     registryName: "Port-MagSafe 3@1", label: label(location, connector: "MagSafe", number: 1),
                     capabilityDescription: "MagSafe 3", isConnected: charger != nil,
                     power: inputMilliwatts.map { PortPower(direction: .input, milliwatts: $0, source: .telemetry) },
                     charger: charger)
    }

    static func hdmi(location: String = "Right Rear", connected: Bool = false) -> PhysicalPort {
        PhysicalPort(key: PortKey(type: PortKey.hdmiType, number: 1), kind: .hdmi, number: 1,
                     registryName: "Port-HDMI@1", label: label(location, connector: "HDMI", number: 1),
                     supportedTransports: [.hdmi], isConnected: connected,
                     link: connected ? LinkInfo(family: .hdmi, generation: "HDMI") : nil)
    }

    // MARK: Power

    static func charger(name: String? = "96W USB-C Power Adapter", watts: Int = 96, serial: String? = nil,
                        port: PortKey? = PortKey(type: PortKey.magSafeType, number: 1)) -> ChargerInfo {
        ChargerInfo(name: name, manufacturer: "Apple Inc.", ratedWatts: watts, millivolts: 20_000, milliamps: 4_700,
                    profiles: [
                        PowerProfile(index: 0, millivolts: 5_000, maxMilliamps: 3_000),
                        PowerProfile(index: 1, millivolts: 9_000, maxMilliamps: 3_000),
                        PowerProfile(index: 2, millivolts: 20_000, maxMilliamps: 4_700, isActive: true),
                    ],
                    portKey: port, familyDescription: "USB-C PD", serialNumber: serial)
    }

    // MARK: Snapshots

    static func snapshot(machine: MachineSummary = laptop(), ports: [PhysicalPort] = [],
                         otherDevices: [DeviceNode] = [], displays: [DisplayInfo] = [],
                         power: PowerSummary = PowerSummary(hasBattery: true), diagnostics: [Diagnostic] = [],
                         captureNotes: [String] = [], at date: Date = date) -> HostSnapshot {
        HostSnapshot(capturedAt: date, machine: machine, ports: ports, otherDevices: otherDevices, displays: displays,
                     power: power, diagnostics: diagnostics, captureNotes: captureNotes)
    }

    /// A busy desk setup used by the export and text-tree tests.
    static func studioDesk(serials: Bool = true) -> HostSnapshot {
        let t9 = usbDevice("usb:0x01110000:04e8:61fb", "Samsung T9", bps: 10_000_000_000, milliwatts: 4_500,
                           serial: serials ? "S6XYZ123" : nil,
                           properties: ["USB Serial Number": "S6XYZ123", "idVendor": 1256, "bcdUSB": 0x0320])
        let keyboard = usbDevice("usb:0x01120000:05ac:029c", "Magic Keyboard", kind: .keyboard, bps: 12_000_000,
                                 milliwatts: 500, usbVersion: "2.0")
        let dock = DeviceNode(id: "tb:a1b2c3d4", registryID: 4_200, bus: .thunderbolt, kind: .dock, name: "CalDigit TS4",
                              vendorName: "CalDigit", link: thunderboltLink(40), isTunneled: false, chainDepth: 1,
                              children: [t9, keyboard],
                              properties: ["Device Model Name": "TS4", "ConnectionUUID": "5F1C-77AA"])
        let flash = usbDevice("usb:0x03100000:0781:5581", "Flash Drive", bps: 480_000_000, milliwatts: 500,
                              usbVersion: "3.0", serial: serials ? "4C530001" : nil)
        let receiver = usbDevice("usb:0x00200000:046d:c52b", "USB Receiver", kind: .wireless, bps: 12_000_000,
                                 milliwatts: 100, usbVersion: "2.0")

        let ports = [
            magSafe(charger: charger(serial: serials ? "C0ABC4567" : nil), inputMilliwatts: 61_000),
            usbC(1, "Left Center", link: thunderboltLink(40),
                 power: PortPower(direction: .output, milliwatts: 5_000, source: .usbAllocation), devices: [dock],
                 properties: ["ConnectionUUID": "9D0E-1234", "PortTypeDescription": "USB-C"]),
            usbC(2, "Left Front"),
            hdmi(connected: true),
            usbC(3, "Right Center", link: usbLink(480_000_000),
                 power: PortPower(direction: .output, milliwatts: 500, source: .usbAllocation), devices: [flash]),
        ]
        let displays = [
            DisplayInfo(id: "display:1552:41006:987654", name: "Studio Display", vendorID: 1552, productID: 41006,
                        serialNumber: serials ? 987_654 : nil, isBuiltin: false, pixelWidth: 5120, pixelHeight: 2880,
                        refreshHz: 60, portKey: PortKey(type: PortKey.usbCType, number: 1),
                        link: LinkInfo(family: .displayPort, generation: "DisplayPort")),
            DisplayInfo(id: "display:builtin", name: "Color LCD", isBuiltin: true, pixelWidth: 3024, pixelHeight: 1964,
                        refreshHz: 120),
        ]
        let power = PowerSummary(
            charger: charger(serial: serials ? "C0ABC4567" : nil),
            battery: BatteryInfo(percent: 82, isCharging: true, externalConnected: true, powerMilliwatts: 40_000),
            systemInputMilliwatts: 61_000, systemLoadMilliwatts: 21_000, portOutputMilliwatts: 5_500,
            usbAllocatedMilliwatts: 5_600, hasBattery: true)
        let diagnostics = [
            Diagnostic(id: "usb2Fallback:usb:0x03100000:0781:5581", kind: .usb2Fallback, severity: .warning,
                       title: "Flash Drive is running at USB 2 speed",
                       detail: "Flash Drive supports USB 3.0 but is connected at 480 Mb/s on Right Center · USB-C.",
                       suggestion: "Try another cable.", portKey: PortKey(type: PortKey.usbCType, number: 3),
                       deviceID: "usb:0x03100000:0781:5581"),
        ]
        return snapshot(ports: ports, otherDevices: [receiver], displays: displays, power: power,
                        diagnostics: diagnostics)
    }

    // MARK: Raw

    /// A raw capture with serial numbers in every place a capture can hold them.
    static func rawCapture() -> RawSnapshot {
        let port = RawNode(id: 0x1000_0101, parentID: 0x1000_0100, className: "AppleHPMInterfaceType10",
                           classChain: ["AppleHPMInterfaceType10", "AppleHPMInterface", "IOPort"], name: "Port-USB-C",
                           location: "1", properties: [
                               "PortTypeDescription": "USB-C", "PortType": 2, "PortNumber": 1, "BuiltIn": true,
                               "ConnectionUUID": "C0FFEE-0001", "TransportsSupported": ["CC", "USB2", "USB3", "CIO"],
                               "Overcurrent Count": 0, "FW Version": .data(Data([0x00, 0x99, 0x30, 0x00])),
                           ])
        let transport = RawNode(id: 0x1000_0102, parentID: 0x1000_0101, className: "IOPortTransportStateUSB2",
                                name: "USB2", properties: [
                                    "Active": true, "Serial Number": "2407E8CE7167", "Product": "CT4000X10PROSSD9",
                                    "Metadata": ["Serial Number": "2407E8CE7167", "Vendor ID": 1588],
                                ])
        let device = RawUSBDevice(
            node: RawNode(id: 0x1000_0200, className: "IOUSBHostDevice", name: "CT4000X10PROSSD9", location: "00110000",
                          properties: [
                              "USB Product Name": "CT4000X10PROSSD9", "USB Vendor Name": "Micron",
                              "USB Serial Number": "2407E8CE7167", "kUSBSerialNumberString": "2407E8CE7167",
                              "idVendor": 1588, "idProduct": 22020, "bcdUSB": 528, "UsbLinkSpeed": 480_000_000,
                              "UsbPowerSinkAllocation": 500, "locationID": 1_114_112,
                          ]),
            ancestry: [RawAncestor(id: 0x1000_0150, className: "AppleT8132USBXHCI", name: "usb-drd0")],
            usbIOPortPath: "IOService:/AppleARMPE/arm-io/AppleHPMDevice@3F/Port-USB-C@1",
            drdPortNumber: 1, ioPortParentID: 0x1000_0102,
            interfaces: [RawUSBInterface(interfaceClass: 8, interfaceSubClass: 6, interfaceProtocol: 80)])
        let hostSwitch = RawThunderboltSwitch(
            node: RawNode(id: 0x2000_0001, className: "IOThunderboltSwitchType7", name: "IOThunderboltSwitchType7",
                          properties: ["UID": 0x0123_4567_89ab_cdef, "Depth": 0, "Device Model Name": "MacBook Pro"]),
            ports: [RawNode(id: 0x2000_0002, className: "IOThunderboltPort", name: "IOThunderboltPort", location: "1",
                            properties: ["Port Number": 1, "Socket ID": "1", "Description": "Thunderbolt Port",
                                         "Current Link Speed": 2, "Supported Link Speed": 14,
                                         "DROM": ["Serial": "TB-SERIAL-1"]])],
            ancestry: [RawAncestor(id: 0x2000_0000, className: "AppleThunderboltHALType7", name: "acio0")])
        return RawSnapshot(
            capturedAt: date,
            machine: MachineInfo(model: "Mac17,5", targetType: "J700", chip: "Apple A18 Pro", osVersion: "27.0",
                                 osBuild: "27A100", hasBattery: true, computerName: "Jordan's MacBook Neo"),
            portNodes: [port, transport],
            portControllerUUIDs: ["2/1": "9a8b7c6d5e4f"],
            usbDevices: [device],
            thunderboltSwitches: [hostSwitch],
            battery: [
                "ExternalConnected": true, "IsCharging": true, "CurrentCapacity": 34, "Serial": "F8Y2BATTERY",
                "AdapterDetails": ["Name": "30W USB-C Power Adapter", "Watts": 30, "SerialString": "C4H2ADAPTER",
                                   "UsbHvcMenu": [["Index": 0, "MaxVoltage": 5000, "MaxCurrent": 2960]]],
                "PowerTelemetryData": ["SystemPowerIn": 28217, "SystemLoad": 4230, "BatteryPower": 23987],
                "ChargerData": ["NotChargingReason": 0, "IsCharging": true],
            ],
            adapter: ["Watts": 30, "SerialNumber": "C4H2ADAPTER", "Current": 1490, "AdapterVoltage": 20000],
            smcChannels: [SMCChannel(index: 1, uuid: "9a8b7c6d5e4f", volts: 5.02, amps: 0.9, present: true)],
            displays: [RawDisplay(id: 1, name: "Color LCD", isBuiltin: true, isMain: true, pixelWidth: 2560,
                                  pixelHeight: 1664, refreshHz: 60),
                       RawDisplay(id: 2, name: "LG UltraFine", vendorID: 7789, productID: 23305,
                                  serialNumber: 556_677, isBuiltin: false, pixelWidth: 3840, pixelHeight: 2160,
                                  refreshHz: 59.94)],
            captureNotes: ["SMC unavailable"])
    }

    /// Serial numbers and other identifying values used in the fixtures.
    static let secrets = [
        "S6XYZ123", "4C530001", "C0ABC4567", "987654", "5F1C-77AA", "9D0E-1234",
        "2407E8CE7167", "C0FFEE-0001", "TB-SERIAL-1", "F8Y2BATTERY", "C4H2ADAPTER", "556677", "Jordan's MacBook Neo",
    ]
}
