import Foundation

/// One catalogue row: where a numbered connector sits on a given chassis.
public struct PortLocationEntry: Sendable, Hashable, Codable {
    /// "usb-c", "magsafe", "usb-a", "hdmi", "sd", "thunderbolt", "ethernet", "audio".
    public var connector: String
    public var portNumber: Int
    /// "Left Rear", "Right Center", "Front (left)", "Rear".
    public var location: String
    /// "Thunderbolt 5", "Thunderbolt / USB 4", "USB 3 (10 Gb/s)", "MagSafe 3".
    public var capability: String?

    public init(connector: String, portNumber: Int, location: String, capability: String? = nil) {
        self.connector = connector
        self.portNumber = portNumber
        self.location = location
        self.capability = capability
    }
}

/// A chassis description keyed by `hw.model`.
public struct MachineCatalogEntry: Sendable, Hashable, Codable {
    public var model: String
    public var marketingName: String
    public var chassis: String?
    public var ports: [PortLocationEntry]

    public init(model: String, marketingName: String, chassis: String? = nil, ports: [PortLocationEntry]) {
        self.model = model
        self.marketingName = marketingName
        self.chassis = chassis
        self.ports = ports
    }
}

/// Physical port locations per Mac model.
///
/// Data derived from PortScope's `MacPortLocations.json`
/// (https://github.com/azenla/portscope, MIT, © 2026 Alex Zenla).
/// See THIRD_PARTY_NOTICES.md.
public enum PortLocationCatalog {
    /// The catalogue entry for a model, if known.
    public static func entry(for model: String) -> MachineCatalogEntry? {
        nil
    }

    /// Marketing name for a model ("MacBook Pro (14-inch, M5, 2025)"), if known.
    public static func marketingName(for model: String) -> String? {
        entry(for: model)?.marketingName
    }

    /// Every model in the catalogue.
    public static var allModels: [String] {
        []
    }
}
