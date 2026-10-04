import Foundation
@testable import BusStopCore

/// A real capture, transcribed by hand.
///
/// Port-controller nodes come from a macOS 26.3 (25D2140) `IOPort`-plane dump
/// of a MacBook Neo (A18 Pro, `AppleHPMInterfaceType18`): two USB-C ports, a
/// Micron SSD on port 2 running over USB 2, and an Apple 20 W charger
/// identifying itself on port 1 (`ioref/ioregistry-IOPort.txt`). The inductive
/// `Port-Inductive@101` node is kept to check that it is skipped. Driver
/// plumbing keys that the builder never reads are left out.
///
/// The battery service is a macOS 27 MacBook Air M2 `AppleSmartBattery`
/// capture (`ioref/sb_air_m2_27.json`), embedded verbatim, with a 30 W
/// adapter. The two sources are from different Macs; together they exercise
/// every path the builder takes on a laptop.
enum MacBookNeoFixture {
    static let model = "Mac17,5"

    // Registry IDs from the dump.
    static let rootID: UInt64 = 0x1_0000_0100
    static let inductiveID: UInt64 = 0x1_0000_03FB
    static let port2ID: UInt64 = 0x1_0000_0440
    static let port2CCID: UInt64 = 0x1_0000_05B6
    static let port2LDCMID: UInt64 = 0x1_0000_05B7
    static let port2USB2ID: UInt64 = 0x1_0000_1D05
    static let ssdID: UInt64 = 0x1_0000_1D12
    static let port1ID: UInt64 = 0x1_0000_043D
    static let port1CCID: UInt64 = 0x1_0000_05D3
    static let port1SOPID: UInt64 = 0x1_0000_1C1D
    static let port1UVDMID: UInt64 = 0x1_0000_1C1E
    static let port1LDCMID: UInt64 = 0x1_0000_05D5

    static func raw() -> RawSnapshot {
        RawSnapshot(capturedAt: TopologyFixtures.date,
                    machine: MachineInfo(model: model, targetType: nil, chip: "Apple A18 Pro", osVersion: "26.3",
                                         osBuild: "25D2140", hasBattery: true),
                    portNodes: portNodes, usbDevices: [ssd], battery: battery)
    }

    static var portNodes: [RawNode] {
        [inductive, port2, port2CC, port2LDCM, port2USB2, port1, port1CC, port1SOP, port1UVDM, port1LDCM]
    }

    static let inductive = RawNode(
        id: inductiveID, parentID: rootID, className: "AppleDockConnectAIC", name: "Port-Inductive", location: "101",
        properties: [
            "ConnectionActive": false,
            "TransportsSupported": [],
            "TransportsActive": [],
            "PortDescription": "Port-Inductive@101",
            "ConnectionCount": 0,
            "FeaturesEnabled": [],
            "IOAccessoryUSBActive": true,
            "PortType": 14,
            "PortNumber": 101,
            "PortTypeDescription": "Inductive",
            "BuiltIn": false,
            "Description": "Port-Inductive@101",
            "IOPersonalityPublisher": "com.apple.driver.AppleDockConnect",
        ])

    static let port2 = RawNode(
        id: port2ID, parentID: rootID, className: "AppleHPMInterfaceType18", name: "Port-USB-C", location: "2",
        properties: [
            "IOAccessoryActivePowerMode": 1,
            "PortTypeDescription": "USB-C",
            "FeaturesEnabled": ["TRM", "LDCM"],
            "IOPersonalityPublisher": "com.apple.driver.AppleHPM",
            "FW Version": .data(Data([0x00, 0x99, 0x30, 0x00])),
            "ActiveCable": false,
            "IOAccessoryPowerMode": 3,
            "ConnectionCount": 2,
            "LDCM_StateDescription": "Idle",
            "IOAccessoryUSBConnectType": 4,
            "Pin Configuration": ["sbu1": 0, "tx1": 1, "rx2": 0, "tx2": 0, "sbu2": 0, "rx1": 2],
            "IOProbeScore": 110,
            "IOClass": "AppleHPMInterfaceType18",
            "LDCM_State": 1,
            "IOAccessoryPrimaryDevicePort": 258,
            "OpticalCable": false,
            "Description": "Port-USB-C@2",
            "BuiltIn": true,
            "TransportsProvisioned": ["CC", "USB2"],
            "Overcurrent Count": 0,
            // Stale: says SuperSpeed while TransportsActive has only USB2.
            "IOAccessoryUSBSuperSpeedActive": true,
            "AuthorizationRequired": true,
            "IOAccessoryUSBConnectString": "Device",
            "TransportsSupported": ["CC", "USB2"],
            "IOAccessoryUSBActive": true,
            "UserAuthorizationStatusDescription": "Authorized",
            "HPDAsserted": false,
            "PortDescription": "Port-USB-C@2",
            "ConnectionActive": true,
            "DisplayPortPinAssignment": 0,
            "PortType": 2,
            "PlugOrientation": 1,
            "IOProviderClass": "AppleHPMDeviceHAL",
            "LDCM_LiquidDetected": false,
            "PortNumber": 2,
            "TransportsActive": ["CC", "USB2"],
            "Plug Event Count": 2,
            "ConnectionUUID": "5847D240-EB85-4E03-9E5E-5656448E5EBB",
        ])

    static let port2CC = RawNode(
        id: port2CCID, parentID: port2ID, className: "IOPortTransportStateCC", name: "CC",
        properties: [
            "ParentPortType": 2,
            "ParentPortBuiltIn": true,
            "ParentBuiltInPortType": 2,
            "Tunneled": false,
            "ParentPortTypeDescription": "USB-C",
            "TransportType": 1,
            "ParentBuiltInPortNumber": 2,
            "ParentPortNumber": 2,
            "TransportTypeDescription": "CC",
            "TransportDescription": "Port-USB-C@2/CC",
            "Active": true,
        ])

    static let port2LDCM = RawNode(
        id: port2LDCMID, parentID: port2ID, className: "AppleHPMLDCMType2", name: "LDCM",
        properties: [
            "ParentPortType": 2,
            "StateDescription": "Hardware Controlled",
            "ParentBuiltInPortType": 2,
            "FeatureTypeDescription": "LDCM",
            "LiquidDetected": false,
            "ParentBuiltInPortNumber": 2,
            "ParentPortNumber": 2,
            "Description": "Port-USB-C@2/LDCM",
        ])

    static let port2USB2 = RawNode(
        id: port2USB2ID, parentID: port2ID, className: "IOPortTransportStateUSB2", name: "USB2",
        properties: [
            "TransportTypeDescription": "USB2",
            "TRM_TransportRestricted": false,
            "TransportDescription": "Port-USB-C@2/USB2",
            "ParentBuiltInPortNumber": 2,
            "ParentBuiltInPortType": 2,
            "Tunneled": false,
            "DataRole": 2,
            "DataRateDescription": "480 Mbps (High Speed)",
            "TransportType": 2,
            "Active": true,
            "Vendor ID": 1588,
            "Product": "CT4000X10PROSSD9",
            "Product ID": 22020,
            "Metadata": [
                "Device Class": 0, "Manufacturer": "Micron", "Device Subclass": 0, "Vendor ID": 1588,
                "Product ID": 22020, "Product": "CT4000X10PROSSD9", "Device Protocol": 0,
                "Serial Number": "2407E8CE7167", "Device Function": 0,
            ],
            "GenerationDescription": "USB 2.0",
            "DataRate": 3,
            "Serial Number": "2407E8CE7167",
            "ParentPortType": 2,
            "ParentPortNumber": 2,
            "DataRoleDescription": "Host",
            "Generation": 1,
            "Manufacturer": "Micron",
        ])

    static let port1 = RawNode(
        id: port1ID, parentID: rootID, className: "AppleHPMInterfaceType18", name: "Port-USB-C", location: "1",
        properties: [
            "PortTypeDescription": "USB-C",
            "FeaturesEnabled": ["TRM", "LDCM"],
            "IOPersonalityPublisher": "com.apple.driver.AppleHPM",
            "ActiveCable": false,
            "ConnectionCount": 3,
            "Pin Configuration": ["sbu1": 0, "tx1": 0, "rx2": 4, "tx2": 3, "sbu2": 0, "rx1": 0],
            "OpticalCable": false,
            "Description": "Port-USB-C@1",
            "BuiltIn": true,
            "TransportsProvisioned": ["CC"],
            "Overcurrent Count": 0,
            "AuthorizationRequired": false,
            "TransportsSupported": ["CC", "USB2", "USB3", "DisplayPort"],
            "IOAccessoryUSBActive": true,
            "PortDescription": "Port-USB-C@1",
            "ConnectionActive": true,
            "DisplayPortPinAssignment": 0,
            "PortType": 2,
            "PlugOrientation": 1,
            "IOAccessoryID": .int(-1),
            "LDCM_LiquidDetected": false,
            "PortNumber": 1,
            "TransportsActive": ["CC"],
            "Plug Event Count": 2,
            "ConnectionUUID": "FAB637E1-F2D7-40EF-9873-9FDE8237EFA1",
        ])

    static let port1CC = RawNode(
        id: port1CCID, parentID: port1ID, className: "IOPortTransportStateCC", name: "CC",
        properties: [
            "ParentPortType": 2,
            "ParentBuiltInPortType": 2,
            "Tunneled": false,
            "TransportType": 1,
            "ParentBuiltInPortNumber": 1,
            "ParentPortNumber": 1,
            "TransportTypeDescription": "CC",
            "TransportDescription": "Port-USB-C@1/CC",
            "Active": true,
        ])

    static let port1SOP = RawNode(
        id: port1SOPID, parentID: port1CCID, className: "IOPortTransportComponentCCUSBPDSOP", name: "SOP",
        properties: [
            "ParentPortTypeDescription": "USB-C",
            "Metadata": [:],
            "AddressDescription": "SOP",
            "Description": "Port-USB-C@1/CC/SOP",
            "ParentBuiltInPortNumber": 1,
            "Specification Revision": 2,
            "ComponentName": "SOP",
            "ParentTransportType": 1,
            "Address": 1,
            "ParentPortType": 2,
            "ParentTransportTypeDescription": "Port-USB-C@1/CC",
            "ParentPortNumber": 1,
            "ParentBuiltInPortType": 2,
        ])

    static let port1UVDM = RawNode(
        id: port1UVDMID, parentID: port1SOPID, className: "IOPortTransportProtocolAppleUVDM", name: "AppleUVDM",
        properties: [
            "ParentBuiltInPortNumber": 1,
            "ParentComponentName": "SOP",
            "Product": "0",
            "Serial Number": "C4H550612L2PF4FCR",
            "Model": "0x7004",
            "ProtocolName": "AppleUVDM",
            "User String": "20W USB-C Power Adapter",
            "ParentPortType": 2,
            "Manufacturer": "0x05AC",
            "ParentPortNumber": 1,
            "Description": "Port-USB-C@1/CC/SOP/AppleUVDM",
            "ParentComponentDescription": "Port-USB-C@1/CC/SOP",
            "Vendor": "Apple Inc.",
            "Hardware Version": "1.0",
            "Firmware Version": "01040044",
        ])

    static let port1LDCM = RawNode(
        id: port1LDCMID, parentID: port1ID, className: "AppleHPMLDCMType2", name: "LDCM",
        properties: [
            "ParentPortType": 2,
            "FeatureTypeDescription": "LDCM",
            "LiquidDetected": false,
            "ParentBuiltInPortNumber": 1,
            "ParentPortNumber": 1,
            "Description": "Port-USB-C@1/LDCM",
        ])

    /// The Micron SSD, an `IOPort`-plane child of port 2's USB2 transport.
    /// The capture adds its mass-storage interface (UAS).
    static let ssd = RawUSBDevice(
        node: RawNode(id: ssdID, className: "IOUSBHostDevice", name: "CT4000X10PROSSD9", location: "00110000",
                      properties: [
                          "kUSBSerialNumberString": "2407E8CE7167",
                          "bDeviceClass": 0,
                          "UsbLinkSpeed": 480_000_000,
                          "bDeviceSubClass": 0,
                          "iSerialNumber": 3,
                          "Usb3LinkPreferred": true,
                          "iProduct": 2,
                          "USB Serial Number": "2407E8CE7167",
                          "USB Vendor Name": "Micron",
                          "USBSpeed": 3,
                          "bNumConfigurations": 1,
                          "kUSBProductString": "CT4000X10PROSSD9",
                          "kUSBVendorString": "Micron",
                          "USB Product Name": "CT4000X10PROSSD9",
                          "iManufacturer": 1,
                          "idVendor": 1588,
                          "Device Speed": 2,
                          "kUSBCurrentConfiguration": 1,
                          "idProduct": 22020,
                          "bcdDevice": 22020,
                          "sessionID": 186_346_213_132,
                          "USB Address": 2,
                          "USBPortType": 5,
                          "UsbPowerSinkAllocation": 500,
                          "bDeviceProtocol": 0,
                          "locationID": 1_114_112,
                          "kUSBAddress": 2,
                          "bcdUSB": 528,
                          "bMaxPacketSize0": 64,
                          "IOProbeScore": 0,
                      ]),
        ancestry: [
            RawAncestor(id: 0x1_0000_1D00, className: "AppleUSB20XHCITypeCPort", name: "usb-drd1-port-hs",
                        location: "01100000"),
            RawAncestor(id: 0x1_0000_0E00, className: "AppleT8140USBXHCI", name: "AppleT8140USBXHCI",
                        location: "01000000"),
            RawAncestor(id: 0x1_0000_0D00, className: "AppleARMIODevice", name: "usb-drd1"),
        ],
        ioPortParentID: port2USB2ID,
        interfaces: [RawUSBInterface(interfaceClass: 8, interfaceSubClass: 6, interfaceProtocol: 0x62)])

    // MARK: - Battery

    /// `AppleSmartBattery` on a MacBook Air M2, macOS 27 (`sb_air_m2_27.json`).
    static let batteryJSON = #"""
    {
      "AdapterDetails": {
        "AdapterID": 28675,
        "AdapterPowerTier": 2,
        "AdapterVoltage": 20000,
        "Current": 1490,
        "Description": "pd charger",
        "FamilyCode": -536854518,
        "FwVersion": "01030053",
        "HwVersion": "1.0",
        "IsWireless": 0,
        "Manufacturer": "Apple Inc.",
        "Model": "0x7003",
        "Name": "30W USB-C Power Adapter",
        "PMUConfiguration": 1490,
        "SerialString": "<redacted>",
        "UsbHvcHvcIndex": 3,
        "UsbHvcMenu": [
          { "Index": 0, "MaxCurrent": 2960, "MaxVoltage": 5000 },
          { "Index": 1, "MaxCurrent": 2980, "MaxVoltage": 9000 },
          { "Index": 2, "MaxCurrent": 1990, "MaxVoltage": 15000 },
          { "Index": 3, "MaxCurrent": 1490, "MaxVoltage": 20000 }
        ],
        "Watts": 30
      },
      "AdapterInfo": 0,
      "Amperage": 2019,
      "AppleRawBatteryVoltage": 11842,
      "AppleRawExternalConnected": 1,
      "AtCriticalLevel": 0,
      "AvgTimeToEmpty": 65535,
      "AvgTimeToFull": 160,
      "BatteryData": {
        "AbsoluteCapacity": 0,
        "AvgTimeToEmpty": 65535,
        "BatteryPower": 23908,
        "CurrentCapacity": 34,
        "DesignCapacity": 4563,
        "FullChargeCapacity": 4427,
        "FullyCharged": 0,
        "MaxCapacity": 100,
        "NominalChargeCapacity": 4554,
        "RemainingCapacity": 1461,
        "TrueRemainingCapacity": 0
      },
      "BatteryInstalled": 1,
      "BatteryInvalidWakeSeconds": 30,
      "BatteryPackCount": 1,
      "BestAdapterIndex": 0,
      "BootPathUpdated": 1785304221,
      "BootVoltage": 0,
      "ChargerConfiguration": 1416,
      "ChargerCount": 1,
      "ChargerData": {
        "IsCharging": 1,
        "NotChargingReason": 0,
        "PMUConfiguration": 1490,
        "PMUConfigured": 1416,
        "SlowChargingReason": 0,
        "TimeChargingThermallyLimited": 0
      },
      "CurrentCapacity": 34,
      "CycleCount": 37,
      "DesignCycleCount9C": 1000,
      "DeviceName": "bq40z651",
      "ExternalChargeCapable": 1,
      "ExternalConnected": 1,
      "FullPathUpdated": 1785304833,
      "FullyCharged": 0,
      "InstantAmperage": 2019,
      "IsCharging": 1,
      "Location": 0,
      "ManufacturerData": "<redacted>",
      "MaxCapacity": 100,
      "PostChargeWaitSeconds": 120,
      "PostDischargeWaitSeconds": 120,
      "PowerDistribution": {
        "IPDChargingAllowed": 1,
        "IPDInputCurrent": 1490,
        "IPDInputPower": 29800,
        "IPDInputVoltage": 20000,
        "IPDRatioOverride": 255,
        "IPDWattageOverride": 30000
      },
      "PowerTelemetryData": {
        "AccumSystemEffectiveTotalLoad": 0,
        "AccumSystemEffectiveTotalLoadCount": 0,
        "AccumulatedAdapterEfficiencyLoss": 454964,
        "AccumulatedBatteryDischarge": -630,
        "AccumulatedBatteryPower": 12742993,
        "AccumulatedSystemEnergyConsumed": 5212399,
        "AccumulatedSystemLoad": 6023301,
        "AccumulatedSystemPowerIn": 18765664,
        "AccumulatedWallEnergyEstimate": 5667363,
        "AdapterEfficiencyLoss": 684,
        "AdapterEfficiencyLossAccumulatorCount": 665,
        "BatteryDischargeAccumulatorCount": 1,
        "BatteryPower": 23987,
        "BatteryPowerAccumulatorCount": 665,
        "PowerTelemetryErrorCount": 0,
        "SystemCurrentIn": 1412,
        "SystemEffectiveTotalLoad": 0,
        "SystemEnergyConsumed": 7838,
        "SystemLoad": 4230,
        "SystemLoadAccumulatorCount": 666,
        "SystemPowerIn": 28217,
        "SystemPowerInAccumulatorCount": 665,
        "SystemVoltageIn": 19977,
        "WallEnergyEstimate": 8522
      },
      "Serial": "<redacted>",
      "SkipperNEIgnoreAtCritical": 0,
      "TimeRemaining": 160,
      "UpdateTime": 1785304833,
      "UserVisiblePathUpdated": 1785304833,
      "Voltage": 11842,
      "built-in": 1
    }
    """#

    /// The battery JSON decoded into a property bag (empty if it fails to decode).
    static var battery: PropertyBag {
        (try? JSONDecoder().decode(PropertyBag.self, from: Data(batteryJSON.utf8))) ?? PropertyBag()
    }
}
