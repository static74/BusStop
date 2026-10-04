/// Property keys read one at a time from services that can disappear while
/// they are read (transport states, PD components, USB devices, Thunderbolt
/// switches). Long-lived port controllers are read in bulk instead.
///
/// The lists come from real `ioreg` dumps (macOS 26.3 `IOPort` plane, iOS 27)
/// and the keys peer projects read. Keys missing on a given Mac are skipped.
enum RegistryKeys {
    /// Keys that clutter output without helping anyone: driver plumbing,
    /// matching metadata and objects IOKit cannot serialise.
    static let noise: Set<String> = [
        "IOGeneralInterest", "IOCFPlugInTypes", "IOPowerManagement", "IOServiceDEXTEntitlements",
        "IOUserClientClass", "IOProbeScore", "IOMatchCategory", "IOMatchedAtBoot", "CFBundleIdentifierKernel",
        "IOClass", "IOKitDiagnostics", "IOConsoleUsers", "UsbDeviceSignature",
    ]

    /// Whether a key is noise (see `noise`, plus `IOFunctionParent*`).
    static func isNoise(_ key: String) -> Bool {
        noise.contains(key) || key.hasPrefix("IOFunctionParent")
    }

    /// Removes noise keys.
    static func cleaned<Value>(_ values: [String: Value]) -> [String: Value] {
        values.filter { !isNoise($0.key) }
    }

    // MARK: Port nodes

    /// Keys every `IOPort`-family child node shares.
    static let portChildCommon: [String] = [
        "Active", "Tunneled", "Index", "Description", "Metadata", "Priority",
        "TransportType", "TransportTypeDescription", "TransportDescription",
        "ParentPortType", "ParentPortNumber", "ParentPortTypeDescription", "ParentPortBuiltIn",
        "ParentBuiltInPortType", "ParentBuiltInPortNumber", "ParentBuiltInPortTypeDescription",
        "ParentTransportType", "ParentTransportTypeDescription", "ParentFeatureType",
        "ParentComponentName", "ParentComponentDescription",
        "AuthorizationRequired", "AuthorizationStatus", "AuthorizationStatusDescription",
        "AuthenticationRequired", "AuthenticationStatus", "AuthenticationStatusDescription",
        "DriverStatus", "DriverStatusDescription", "HashStatus", "HashStatusDescription",
        "TRM_TransportSupervised", "TRM_TransportRestricted", "TRM_State", "TRM_StateDescription",
        "TRM_Profile", "TRM_ProfileDescription", "TRM_DeviceLocked", "TRM_IdentificationRestricted",
        "TRM_CacheMiss", "TRM_RelaxedPeriod", "TRM_GracePeriodReason", "TRM_GracePeriodReasonDescription",
        "Generation", "GenerationDescription", "IOPersonalityPublisher", "IOProviderClass",
    ]

    /// `IOPortTransportStateUSB2` / `USB3`.
    static let usbTransport: [String] = [
        "DataRate", "DataRateDescription", "DataRole", "DataRoleDescription", "PortDataRole",
        "PortDataRoleDescription", "Product", "Manufacturer", "Vendor ID", "Product ID", "Serial Number",
        "Device Class", "Device Subclass", "Device Protocol", "NominalSignalingFrequenciesHz",
        "SignalingFrequenciesGenerationCount", "SuperSpeedSignaling", "SuperSpeedSignalingDescription",
        "LaneCount", "MaxLaneCount", "Role", "RoleDescription",
    ]

    /// `IOPortTransportStateDisplayPort`.
    static let displayPortTransport: [String] = [
        "LaneCount", "MaxLaneCount", "LinkRate", "LinkRateDescription", "MaxLinkRate", "MaxLinkRateDescription",
        "HPD_State", "HPD_StateDescription", "ProductName", "ManufacturerName", "ManufacturerID", "ProductID",
        "SerialNumber", "EDID", "EDIDChanged", "SinkCount", "BranchDeviceID", "BranchDeviceOUI",
        "DFP Type", "DFP Type Description", "DisplayPortPinAssignment", "YearOfManufacture", "WeekOfManufacture",
        "Role", "RoleDescription",
    ]

    /// `IOPortTransportStateCIO` (Thunderbolt / USB4).
    static let cioTransport: [String] = [
        "CableGeneration", "CableSpeed", "CableSpeedDescription", "CableType", "CableTypeDescription",
        "AsymmetricModeSupported", "LegacyAdapter", "LinkTrainingMode", "LinkTrainingModeDescription",
        "TunneledTransportsProvisioned", "TunneledTransportsActive", "TunneledTransportsSupported",
        "Role", "RoleDescription",
    ]

    /// `IOPortFeature*` and `AppleHPMLDCM*`.
    static let feature: [String] = [
        "FeatureType", "FeatureTypeDescription", "PowerSourceName", "PowerSourceType", "PowerSourceOptions",
        "WinningPowerSourceOption", "State", "StateDescription", "LiquidDetected", "MeasurementStatus",
        "MeasurementStatusDescription", "MitigationsEnabled", "MitigationsStatus", "MitigationsSupported",
        "UserOverrideActive", "FirmwareVersion", "HardwareVersion", "ArchitectureVersion", "Owner",
        "RFClientsEnabled", "RFClientMitigationStatusDescription", "RFClientResponseStatusDescription",
        "TransportClientsEnabled", "TransportsBlocked",
    ]

    /// `IOPortTransportComponent*` (USB-PD SOP, SOP', SOP'').
    static let component: [String] = [
        "ComponentName", "ComponentType", "ComponentFunction", "Address", "Address Description",
        "AddressDescription", "Specification Revision", "Specification Revision Description",
        "Vendor ID", "Product ID", "Vendor ID (SOP1)", "Product ID (SOP1)", "Product Type", "Product Type Description",
    ]

    /// `IOPortTransportProtocol*` (Apple UVDM charger identity and similar).
    static let transportProtocol: [String] = [
        "ProtocolName", "User String", "Manufacturer", "Model", "Vendor", "Product", "Firmware Version",
        "Hardware Version", "Serial Number", "Number of VDOs", "Number of Data EPs", "EP Length", "Unknown",
    ]

    /// Keys of port controllers, used when a bulk read fails.
    static let portController: [String] = [
        "PortTypeDescription", "PortType", "PortNumber", "PortDescription", "Description", "BuiltIn",
        "ConnectionActive", "TransportsSupported", "TransportsActive", "TransportsProvisioned",
        "TransportsUnauthorized", "IOAccessoryUSBSuperSpeedActive", "IOAccessoryUSBActive",
        "IOAccessoryUSBConnectString", "IOAccessoryUSBConnectType", "IOAccessoryUSBModeType", "PlugOrientation",
        "ActiveCable", "OpticalCable", "Pin Configuration", "DisplayPortPinAssignment", "Plug Event Count",
        "ConnectionCount", "Overcurrent Count", "IOAccessoryPowerCurrentLimits", "IOAccessoryPowerMode",
        "IOAccessoryActivePowerMode", "IOAccessorySupportedPowerModes", "FeaturesSupported", "FeaturesEnabled",
        "LDCM_LiquidDetected", "LDCM_State", "LDCM_StateDescription", "FW Version", "HPDAsserted",
        "AuthorizationRequired", "UserAuthorizationStatusDescription", "HDMI_HPD", "Metadata",
        "IOPersonalityPublisher", "IOProviderClass", "IOAccessoryManagerType", "IOAccessoryPrimaryDevicePort",
        "SOPVID", "SOPPID", "SOPMfgString",
    ]

    /// Every child-node key, for classes the reader does not recognise.
    static let anyPortChild: [String] = unique(
        portChildCommon + usbTransport + displayPortTransport + cioTransport + feature + component + transportProtocol
    )

    // MARK: USB

    /// `IOUSBHostDevice`. `kUSBContainerID` is left out on purpose: it is a
    /// UUID unique to each device instance, no parser uses it, and captures
    /// should not carry identifiers that work like serial numbers.
    static let usbDevice: [String] = [
        "USB Product Name", "kUSBProductString", "USB Vendor Name", "kUSBVendorString",
        "USB Serial Number", "kUSBSerialNumberString", "idVendor", "idProduct", "bcdDevice", "bcdUSB",
        "bDeviceClass", "bDeviceSubClass", "bDeviceProtocol", "bMaxPacketSize0", "bNumConfigurations",
        "iManufacturer", "iProduct", "iSerialNumber", "locationID", "USB Address", "kUSBAddress", "sessionID",
        "UsbLinkSpeed", "Device Speed", "USBSpeed", "UsbPowerSinkAllocation", "UsbPowerSinkCapability",
        "USBPortType", "UsbTunnel", "Usb3LinkPreferred", "kUSBHubPowerSupply", "kUSBHubPowerSupplyType",
        "Requested Power", "Bus Power Available", "kUSBCurrentConfiguration", "kUSBPreferredConfiguration",
        "kUSBWakePortCurrentLimit", "kUSBSleepPortCurrentLimit", "UsbCPortNumber",
        "Built-In", "non-removable", "UsbEnumerationState", "PortNum", "Low Power Displayed",
    ]

    /// `IOUSBHostInterface`.
    static let usbInterface: [String] = [
        "bInterfaceClass", "bInterfaceSubClass", "bInterfaceProtocol", "bInterfaceNumber",
        "kUSBString", "USB Interface Name",
    ]

    // MARK: Thunderbolt

    /// `IOThunderboltSwitch*`. `UID` is unique to each router, so it works
    /// like a serial number; it is read because the parsers build stable
    /// device ids from it, and redacted exports remove it.
    static let thunderboltSwitch: [String] = [
        "UID", "Route String", "Depth", "Device Vendor Name", "Device Model Name", "Device Vendor ID",
        "Device Model ID", "Vendor ID", "Device ID", "Revision ID", "Router ID", "Upstream Port Number",
        "Max Port Number", "Firmware Version", "Thunderbolt Version", "Generation", "Supported Link Speed",
        "IOPowerManagement", "Link Bandwidth", "USB Port Map", "TRM Policy",
    ]

    /// `IOThunderboltPort` children of a switch.
    static let thunderboltPort: [String] = [
        "Port Number", "Description", "Adapter Type", "Socket ID", "Current Link Speed", "Supported Link Speed",
        "Target Link Speed", "Current Link Width", "Supported Link Width", "Target Link Width", "Link Bandwidth",
        "Hop Table", "PCI Path", "PCI Entry ID", "Dual-Link Port", "Lane", "CLx State", "Max Credits",
        "Required Bandwidth Allocated", "Maximum Bandwidth Allocated", "Buffer Allocation Request",
        "Min Required TMU Mode", "Micro Address", "Thunderbolt Version",
    ]

    // MARK: Power

    /// `AppleSmartBattery`.
    static let battery: [String] = [
        "AdapterDetails", "PowerTelemetryData", "PowerOutDetails", "PortControllerInfo", "ExternalConnected",
        "IsCharging", "FullyCharged", "CurrentCapacity", "MaxCapacity", "NotChargingReason", "BatteryInstalled",
        "ChargerData", "ExternalChargeCapable", "Voltage", "Amperage", "CycleCount", "TimeRemaining",
        "AvgTimeToFull", "AvgTimeToEmpty", "BatteryData", "BestAdapterIndex", "AppleRawExternalConnected",
    ]

    // MARK: Helpers

    private static func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }
}
