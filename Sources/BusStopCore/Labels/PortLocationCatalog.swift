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

    /// True when the catalogue lists this connector as Thunderbolt-capable
    /// ("Thunderbolt 5", "Thunderbolt / USB 4"). False for plain USB ports and
    /// for rows without a capability.
    public var isThunderbolt: Bool {
        capability?.lowercased().contains("thunderbolt") ?? false
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

    /// This model's rows for one connector (`"usb-c"`), in catalogue order.
    public func ports(connector: String) -> [PortLocationEntry] {
        ports.filter { $0.connector == connector }
    }

    /// True for the compact desktops whose front and rear USB-C ports can
    /// differ in capability: Mac mini and Mac Studio.
    public var isCompactDesktop: Bool {
        [marketingName, chassis ?? ""].contains { $0.hasPrefix("Mac mini") || $0.hasPrefix("Mac Studio") }
    }
}

/// Physical port locations per Mac model.
///
/// Data derived from PortScope's `MacPortLocations.json`
/// (https://github.com/azenla/portscope, MIT, © 2026 Alex Zenla).
/// See THIRD_PARTY_NOTICES.md. The rows live in the generated file
/// `PortLocationCatalog+Data.swift`; regenerate it with
/// `scripts/generate-port-catalog.py` rather than editing it.
public enum PortLocationCatalog {
    /// Catalogue entries keyed by `hw.model`. Should the data ever list a
    /// model twice, the first row wins.
    private static let entriesByModel: [String: MachineCatalogEntry] = Dictionary(
        generatedEntries.map { ($0.model, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// The catalogue entry for a model, if known. Surrounding whitespace in
    /// `model` is ignored; otherwise the match is exact (`"Mac16,10"`).
    public static func entry(for model: String) -> MachineCatalogEntry? {
        let key = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return entriesByModel[key]
    }

    /// Marketing name for a model ("MacBook Pro (14-inch, M5, 2025)"), if known.
    public static func marketingName(for model: String) -> String? {
        entry(for: model)?.marketingName
    }

    /// Every model in the catalogue, sorted by model identifier.
    public static var allModels: [String] {
        generatedEntries.map(\.model)
    }

    /// True when `model` is a Mac mini or Mac Studio: from the catalogue, or
    /// from the `Macmini` identifier prefix for models the catalogue lacks.
    public static func isCompactDesktop(model: String) -> Bool {
        if let entry = entry(for: model) { return entry.isCompactDesktop }
        return model.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Macmini")
    }
}
