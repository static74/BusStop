import Foundation

/// Resolves human names for ports. See SPEC §5.4 "Labels".
///
/// Order of precedence:
/// 1. A name the user gave the port.
/// 2. The catalogue row for this model with the same connector and number.
/// 3. The catalogue row at the same rank among same-connector ports, when the
///    Mac numbers its ports differently from the catalogue (an M5 MacBook Pro
///    publishes USB-C ports 1, 2 and 4; the catalogue lists 1, 2 and 3).
/// 4. A location from the port's capability: on a Mac mini or Mac Studio,
///    Thunderbolt ports are at the rear and plain USB-C ports at the front.
/// 5. A generic name such as "USB-C 2".
///
/// Catalogue numbers are not always the kernel's numbers, so a catalogue row
/// is rejected when its capability contradicts the port's (a Thunderbolt row
/// for a port without Thunderbolt, or the reverse) on models whose rows for
/// that connector mix both kinds. Step 4 then names the port instead.
public enum PortLabeler {
    /// Label for one port.
    ///
    /// - Parameters:
    ///   - kind: connector kind of the port.
    ///   - number: IOKit `PortNumber`.
    ///   - key: the port key (for user overrides).
    ///   - siblings: numbers of all ports of the same kind on this Mac (for rank fallback).
    ///     The port's own number is added when missing.
    ///   - model: `hw.model`.
    ///   - userNames: port key string → user name.
    ///   - supportsThunderbolt: whether the port lists `CIO` in `TransportsSupported`,
    ///     used to tell rear Thunderbolt ports from front USB-C ports on desktops.
    /// - Returns: the label, and the catalogue's capability text for the port
    ///   ("Thunderbolt 5") when the catalogue describes it. A user-named port
    ///   keeps the catalogue capability.
    public static func label(kind: PortKind, number: Int, key: PortKey, siblings: [Int], model: String,
                             userNames: [String: String],
                             supportsThunderbolt: Bool? = nil) -> (label: PortLabel, capability: String?) {
        let connector = kind.displayName
        let match = acceptedMatch(kind: kind, number: number, siblings: siblings, model: model,
                                  supportsThunderbolt: supportsThunderbolt)
        let guess = match == nil
            ? capabilityLocation(kind: kind, model: model, supportsThunderbolt: supportsThunderbolt)
            : nil

        if let name = userNames[key.description]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            let label = PortLabel(location: name, source: .user, connector: connector, number: number)
            return (label, match?.row.capability ?? guess?.capability)
        }
        if let match {
            let label = PortLabel(location: match.row.location, source: match.isExact ? .catalog : .catalogRank,
                                  connector: connector, number: number)
            return (label, match.row.capability)
        }
        if let guess {
            // An inference from the catalogue and the port's capability, so it
            // reports the weaker of the two catalogue sources.
            let label = PortLabel(location: guess.location, source: .catalogRank, connector: connector, number: number)
            return (label, guess.capability)
        }
        return (PortLabel(location: nil, source: .generic, connector: connector, number: number), nil)
    }

    /// Physical sort order for ports on a model.
    ///
    /// Ports matched to a catalogue row sort first, in the catalogue's order
    /// (left side rear to front, then right side, as PortScope lists them).
    /// Other ports follow, by kind rank and then number.
    public static func sortKey(kind: PortKind, number: Int, siblings: [Int], model: String,
                               supportsThunderbolt: Bool? = nil) -> (Int, Int, Int) {
        if let match = acceptedMatch(kind: kind, number: number, siblings: siblings, model: model,
                                     supportsThunderbolt: supportsThunderbolt) {
            return (0, match.index, number)
        }
        return (1, kind.sortRank, number)
    }

    // MARK: Catalogue matching

    /// A catalogue row matched to a port.
    struct CatalogMatch: Equatable {
        var row: PortLocationEntry
        /// Position of the row in the model's full catalogue list.
        var index: Int
        /// True when the row's number is the port's own number.
        var isExact: Bool
    }

    /// The catalogue row for a port by number or rank, before any capability check.
    ///
    /// When every port number on this Mac appears in the catalogue, rows are
    /// matched by number. Otherwise, when the Mac has as many ports of this
    /// kind as the catalogue lists, the n-th lowest number takes the n-th
    /// lowest row; this keeps the mapping one-to-one where a mix of exact and
    /// ranked matches could give two ports the same row. When the counts
    /// differ too, only exact numbers match.
    static func catalogMatch(kind: PortKind, number: Int, siblings: [Int], model: String) -> CatalogMatch? {
        guard let machine = PortLocationCatalog.entry(for: model) else { return nil }
        let connector = kind.catalogConnector
        let rows = machine.ports.enumerated().filter { $0.element.connector == connector }
        guard !rows.isEmpty else { return nil }

        func match(_ row: (offset: Int, element: PortLocationEntry)) -> CatalogMatch {
            CatalogMatch(row: row.element, index: row.offset, isExact: row.element.portNumber == number)
        }
        let exact = rows.first { $0.element.portNumber == number }.map(match)

        let numbers = Set(siblings).union([number]).sorted()
        let catalogNumbers = Set(rows.map(\.element.portNumber))
        if numbers.allSatisfy(catalogNumbers.contains) {
            return exact
        }
        if numbers.count == rows.count, let rank = numbers.firstIndex(of: number) {
            let ranked = rows.sorted { ($0.element.portNumber, $0.offset) < ($1.element.portNumber, $1.offset) }
            return match(ranked[rank])
        }
        return exact
    }

    /// `catalogMatch`, unless the row's capability contradicts the port's on
    /// a model whose rows for this connector mix Thunderbolt and plain USB.
    static func acceptedMatch(kind: PortKind, number: Int, siblings: [Int], model: String,
                              supportsThunderbolt: Bool?) -> CatalogMatch? {
        guard let match = catalogMatch(kind: kind, number: number, siblings: siblings, model: model) else {
            return nil
        }
        guard let supportsThunderbolt, hasMixedCapabilities(kind: kind, model: model) else { return match }
        return match.row.isThunderbolt == supportsThunderbolt ? match : nil
    }

    /// True when the model's catalogue rows for this connector include both
    /// Thunderbolt and non-Thunderbolt ports (Mac mini M4, Mac Studio M4 Max,
    /// four-port iMac).
    static func hasMixedCapabilities(kind: PortKind, model: String) -> Bool {
        let rows = PortLocationCatalog.entry(for: model)?.ports(connector: kind.catalogConnector) ?? []
        let kinds = Set(rows.map(\.isThunderbolt))
        return kinds.count > 1
    }

    /// The desktop heuristic: a location shared by every catalogue row with
    /// the port's capability ("Rear" for the Mac mini's Thunderbolt ports), or
    /// "Rear" / "Front" on a Mac mini or Mac Studio the catalogue cannot place.
    ///
    /// Applies to USB-C ports with a known Thunderbolt capability on compact
    /// desktops and on models whose rows mix capabilities. Returns nil when
    /// the rows with that capability sit in different places (the front and
    /// rear Thunderbolt ports of a Mac Studio with M1 Ultra).
    static func capabilityLocation(kind: PortKind, model: String,
                                   supportsThunderbolt: Bool?) -> (location: String, capability: String?)? {
        guard kind == .usbC, let supportsThunderbolt else { return nil }
        let isDesktop = PortLocationCatalog.isCompactDesktop(model: model)
        guard isDesktop || hasMixedCapabilities(kind: kind, model: model) else { return nil }

        let rows = PortLocationCatalog.entry(for: model)?.ports(connector: kind.catalogConnector) ?? []
        let sameKind = rows.filter { $0.isThunderbolt == supportsThunderbolt }
        if !sameKind.isEmpty {
            let areas = Set(sameKind.map { area(of: $0.location) })
            guard areas.count == 1, let area = areas.first, !area.isEmpty else { return nil }
            let capabilities = Set(sameKind.compactMap(\.capability))
            return (area, capabilities.count == 1 ? capabilities.first : nil)
        }
        guard isDesktop else { return nil }
        return (supportsThunderbolt ? "Rear" : "Front", nil)
    }

    /// The first word of a catalogue location: "Rear (left)" → "Rear",
    /// "Top/Front (left)" → "Top/Front".
    static func area(of location: String) -> String {
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        let end = trimmed.firstIndex { $0 == " " || $0 == "(" } ?? trimmed.endIndex
        return String(trimmed[..<end])
    }
}
