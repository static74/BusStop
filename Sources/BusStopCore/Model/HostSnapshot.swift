import Foundation

/// A display attached to the Mac.
public struct DisplayInfo: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var vendorID: Int?
    public var productID: Int?
    public var serialNumber: Int?
    public var isBuiltin: Bool
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var refreshHz: Double?
    /// The port the display is attached to, when it could be determined.
    public var portKey: PortKey?
    public var link: LinkInfo?

    public init(id: String, name: String, vendorID: Int? = nil, productID: Int? = nil, serialNumber: Int? = nil,
                isBuiltin: Bool, pixelWidth: Int? = nil, pixelHeight: Int? = nil, refreshHz: Double? = nil,
                portKey: PortKey? = nil, link: LinkInfo? = nil) {
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.isBuiltin = isBuiltin
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshHz = refreshHz
        self.portKey = portKey
        self.link = link
    }

    /// "5120 × 2880 @ 120 Hz"
    public var modeDescription: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        var s = "\(pixelWidth) × \(pixelHeight)"
        if let refreshHz, refreshHz > 0 { s += " @ \(Int(refreshHz.rounded())) Hz" }
        return s
    }
}

/// How serious a diagnostic is.
public enum DiagnosticSeverity: String, Sendable, Hashable, Codable, Comparable, CaseIterable {
    case info
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    public static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool { lhs.rank < rhs.rank }
}

/// The rule that produced a diagnostic.
public enum DiagnosticKind: String, Sendable, Hashable, Codable, CaseIterable {
    case usb2Fallback
    case thunderboltBottleneck
    case slowCharger
    case notCharging
    case hubOverBudget
    case deepChain
    case liquidDetected
    case overcurrent
    case reducedDetail
}

/// A plain-English finding about the current setup.
public struct Diagnostic: Sendable, Hashable, Codable, Identifiable {
    /// Stable for the same rule and subject: `"<kind>:<subject id>"`.
    public var id: String
    public var kind: DiagnosticKind
    public var severity: DiagnosticSeverity
    public var title: String
    public var detail: String
    public var suggestion: String?
    public var portKey: PortKey?
    public var deviceID: String?

    public init(id: String, kind: DiagnosticKind, severity: DiagnosticSeverity, title: String, detail: String,
                suggestion: String? = nil, portKey: PortKey? = nil, deviceID: String? = nil) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestion = suggestion
        self.portKey = portKey
        self.deviceID = deviceID
    }
}

/// The Mac as a whole.
public struct MachineSummary: Sendable, Hashable, Codable {
    /// `hw.model`.
    public var model: String
    /// Marketing name, e.g. "MacBook Pro (14-inch, M5 Pro, 2026)", or the model ID.
    public var name: String
    public var chip: String?
    public var osVersion: String
    public var isLaptop: Bool
    public var isAppleSilicon: Bool

    public init(model: String, name: String, chip: String? = nil, osVersion: String, isLaptop: Bool,
                isAppleSilicon: Bool = true) {
        self.model = model
        self.name = name
        self.chip = chip
        self.osVersion = osVersion
        self.isLaptop = isLaptop
        self.isAppleSilicon = isAppleSilicon
    }
}

/// The interpreted state of the Mac's ports at one moment.
public struct HostSnapshot: Sendable, Hashable, Codable {
    public var capturedAt: Date
    public var machine: MachineSummary
    /// Physical ports in physical order (catalogue order, then kind and number).
    public var ports: [Port]
    /// Devices that could not be tied to a port.
    public var otherDevices: [DeviceNode]
    public var displays: [DisplayInfo]
    public var power: PowerSummary
    public var diagnostics: [Diagnostic]
    public var captureNotes: [String]
    public var isDemo: Bool

    public init(capturedAt: Date, machine: MachineSummary, ports: [Port] = [], otherDevices: [DeviceNode] = [],
                displays: [DisplayInfo] = [], power: PowerSummary = PowerSummary(), diagnostics: [Diagnostic] = [],
                captureNotes: [String] = [], isDemo: Bool = false) {
        self.capturedAt = capturedAt
        self.machine = machine
        self.ports = ports
        self.otherDevices = otherDevices
        self.displays = displays
        self.power = power
        self.diagnostics = diagnostics
        self.captureNotes = captureNotes
        self.isDemo = isDemo
    }

    /// An empty snapshot, used before the first capture completes.
    public static func placeholder(at date: Date = Date(timeIntervalSince1970: 0)) -> HostSnapshot {
        HostSnapshot(capturedAt: date,
                     machine: MachineSummary(model: "Mac", name: "This Mac", osVersion: "", isLaptop: false))
    }

    public var connectedPorts: [Port] { ports.filter(\.isConnected) }

    /// Devices on every port plus unattributed ones, counting every level.
    public var deviceCount: Int {
        ports.reduce(0) { $0 + $1.deviceCount } + otherDevices.reduce(0) { $0 + 1 + $1.descendantCount }
    }

    /// Every device with the port it hangs off (nil for unattributed) and its depth.
    public var allDevices: [(device: DeviceNode, port: Port?, depth: Int)] {
        var result: [(DeviceNode, Port?, Int)] = []
        for port in ports {
            for (device, depth) in port.allDevices { result.append((device, port, depth)) }
        }
        for root in otherDevices {
            for (device, depth) in root.flattened() { result.append((device, nil, depth)) }
        }
        return result
    }

    public func port(_ key: PortKey) -> Port? { ports.first { $0.key == key } }

    /// The port a device hangs off, by device ID.
    public func port(containing deviceID: String) -> Port? {
        ports.first { port in port.allDevices.contains { $0.device.id == deviceID } }
    }

    public func device(id: String) -> DeviceNode? {
        allDevices.first { $0.device.id == id }?.device
    }

    /// The most severe diagnostic, if any.
    public var worstSeverity: DiagnosticSeverity? { diagnostics.map(\.severity).max() }
}
