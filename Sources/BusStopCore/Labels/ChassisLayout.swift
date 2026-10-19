import Foundation

/// The kind of outline the Mac gets: a laptop seen from above, or the
/// front and rear of a desktop.
public enum ChassisFamily: Sendable, Hashable {
    case laptop, macMini, macStudio, macPro, iMac
    /// A desktop the catalogue and the model name do not identify.
    case other

    /// From the marketing or heuristic name ("MacBook", "Mac mini",
    /// "Mac Studio", "Mac Pro", "iMac" prefixes), else `.laptop` when the
    /// Mac has a battery.
    public init(machine: MachineSummary) {
        let prefixes: [(String, ChassisFamily)] = [
            ("MacBook", .laptop), ("Mac mini", .macMini), ("Mac Studio", .macStudio), ("Mac Pro", .macPro),
            ("iMac", .iMac),
        ]
        self = prefixes.first { machine.name.hasPrefix($0.0) }?.1 ?? (machine.isLaptop ? .laptop : .other)
    }
}

/// A side of the Mac that carries ports.
public enum ChassisFace: Sendable, Hashable, CaseIterable {
    case left, right, front, rear
}

/// One drawn connector on the outline.
public struct ChassisSlot: Sendable, Hashable {
    public var face: ChassisFace
    /// 0...1 along the face: rear to front on a laptop side; left to right
    /// in the catalogue's words on a desktop face.
    public var position: Double
    /// Catalogue connector name ("usb-c", "ethernet").
    public var connector: String
    /// The live port, or nil for a catalogue connector macOS does not report
    /// (Ethernet, the power inlet, an SD slot), drawn as a passive outline.
    public var portKey: PortKey?
    /// Catalogue location text, for tooltips of passive slots.
    public var location: String

    public init(face: ChassisFace, position: Double, connector: String, portKey: PortKey?, location: String) {
        self.face = face
        self.position = position
        self.connector = connector
        self.portKey = portKey
        self.location = location
    }
}

/// Where each port sits on the Mac's outline, from the catalogue location
/// the labeler recorded (`PhysicalPort.catalogLocation`). See SPEC §5.4.
public struct ChassisLayout: Sendable, Hashable {
    public var family: ChassisFamily
    /// Every slot, by face (left, right, front, rear) and then position.
    public var slots: [ChassisSlot]
    /// Live ports with no place, in physical order (unknown model, a row the
    /// labeler rejected, a location the parser cannot read).
    public var unplaced: [PortKey]

    public init(family: ChassisFamily, slots: [ChassisSlot], unplaced: [PortKey]) {
        self.family = family
        self.slots = slots
        self.unplaced = unplaced
    }

    /// Lays out `ports` on the outline for `machine`.
    ///
    /// 1. A live port goes where its `catalogLocation` says. Its catalogue
    ///    row is the one with the same connector and location; a port placed
    ///    only by area ("Rear") sorts with the first row of its connector on
    ///    that face, and ties go by port number.
    /// 2. A catalogue row becomes a passive slot when no live port has its
    ///    connector (Ethernet, the power inlet, an SD slot macOS does not
    ///    report). Rows of a connector that has live ports are not drawn
    ///    twice, even when the labeler only placed those ports by area.
    /// 3. Laptop sides sort by rear-center-front, then catalogue order.
    ///    Desktop qualifiers ("left", "right-center") are relative within one
    ///    connector, so desktop faces group by connector in catalogue order
    ///    first. Slot `i` of `n` sits at `(i + 1) / (n + 1)`.
    /// 4. A port with no location, or one the parser cannot read, is unplaced.
    public static func resolve(machine: MachineSummary, ports: [PhysicalPort]) -> ChassisLayout {
        let rows = Array((PortLocationCatalog.entry(for: machine.model)?.ports ?? []).enumerated())

        struct Candidate {
            var face: ChassisFace
            var ordinal: Int
            var index: Int
            var number: Int
            var slot: ChassisSlot
        }
        var candidates: [Candidate] = []
        var unplaced: [PortKey] = []

        for port in ports {
            let connector = port.kind.catalogConnector
            guard let location = port.catalogLocation, let place = parse(location) else {
                unplaced.append(port.key)
                continue
            }
            let index = rows.first { $0.element.connector == connector && $0.element.location == location }?.offset
                ?? rows.first { $0.element.connector == connector && parse($0.element.location)?.face == place.face }?
                    .offset
                ?? Int.max
            candidates.append(Candidate(
                face: place.face, ordinal: place.ordinal, index: index, number: port.number,
                slot: ChassisSlot(face: place.face, position: 0, connector: connector, portKey: port.key,
                                  location: location)))
        }

        let liveConnectors = Set(ports.map(\.kind.catalogConnector))
        for (index, row) in rows where !liveConnectors.contains(row.connector) {
            guard let place = parse(row.location) else { continue }
            candidates.append(Candidate(
                face: place.face, ordinal: place.ordinal, index: index, number: row.portNumber,
                slot: ChassisSlot(face: place.face, position: 0, connector: row.connector, portKey: nil,
                                  location: row.location)))
        }

        // Desktop faces: the connector's first catalogue row on that face.
        func connectorRank(_ candidate: Candidate) -> Int {
            rows.first { row in
                row.element.connector == candidate.slot.connector && parse(row.element.location)?.face == candidate.face
            }?.offset ?? Int.max
        }

        var slots: [ChassisSlot] = []
        for face in ChassisFace.allCases {
            let isSide = face == .left || face == .right
            let onFace = candidates.filter { $0.face == face }.sorted { lhs, rhs in
                let left = (isSide ? 0 : connectorRank(lhs), lhs.ordinal, lhs.index, lhs.number)
                let right = (isSide ? 0 : connectorRank(rhs), rhs.ordinal, rhs.index, rhs.number)
                return left < right
            }
            for (i, candidate) in onFace.enumerated() {
                var slot = candidate.slot
                slot.position = Double(i + 1) / Double(onFace.count + 1)
                slots.append(slot)
            }
        }
        return ChassisLayout(family: ChassisFamily(machine: machine), slots: slots, unplaced: unplaced)
    }

    /// "Left Rear" → (.left, 0); "Rear (left-center)" → (.rear, 2);
    /// "Top/Front (right)" → (.front, 5); "Rear" → (.rear, 3). Nil when unreadable.
    /// Laptop ordinals: Rear 0, Center 1, Front 2. Desktop ordinals: leftmost 0 …
    /// center 3 … rightmost 6; no qualifier is the centre.
    static func parse(_ location: String) -> (face: ChassisFace, ordinal: Int)? {
        let text = location.trimmingCharacters(in: .whitespaces)
        let sides: [String: ChassisFace] = ["Left": .left, "Right": .right]
        let alongSide = ["Rear", "Center", "Front"]
        let words = text.split(separator: " ").map(String.init)
        if words.count == 2, let face = sides[words[0]], let ordinal = alongSide.firstIndex(of: words[1]) {
            return (face, ordinal)
        }

        let areas: [String: ChassisFace] = ["Front": .front, "Top/Front": .front, "Rear": .rear,
                                            "Rear I/O card": .rear]
        let qualifiers = ["leftmost", "left", "left-center", "center", "right-center", "right", "rightmost"]
        guard let open = text.firstIndex(of: "(") else {
            return areas[text].map { ($0, 3) }
        }
        let area = text[..<open].trimmingCharacters(in: .whitespaces)
        guard text.hasSuffix(")"), let face = areas[area] else { return nil }
        let qualifier = text[text.index(after: open)..<text.index(before: text.endIndex)]
        guard let ordinal = qualifiers.firstIndex(of: String(qualifier)) else { return nil }
        return (face, ordinal)
    }
}
