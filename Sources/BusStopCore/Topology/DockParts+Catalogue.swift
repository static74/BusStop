import Foundation

extension DockParts {
    /// USB parts built into docks and displays, by the Thunderbolt switch's
    /// `Device Vendor ID` / `Device Model ID`: the USB vendor and product IDs
    /// of those parts.
    ///
    /// An entry is the whole list of what the product contains, so it does
    /// two things. It limits rules C and E: in a listed product they fold only
    /// listed devices, and E folds nothing in a product without an entry,
    /// because captive flags cannot tell the dock's own Ethernet from a
    /// keyboard on a dock port wired to the same hub. And it drives rule G,
    /// for products whose own flags do not show their parts: a listed device
    /// folds when it is the one listed device on the root hub's ports, or sits
    /// on a captive port of a part G folded and reports no container ID that
    /// its parent part does not. A device on a standard port, such as one a
    /// user plugged into the monitor, stays whatever its IDs.
    ///
    /// Each entry comes from a capture of that model (`busstop --raw`) and
    /// its `kUSBContainerID` grouping; see CONTRIBUTING.md.
    static let catalogue: [Identity: Set<Identity>] = [
        // Anker Prime Docking Station (14-in-1, 8K, Thunderbolt 5): A, B and D find its Intel root hub, its
        // own two functions and the VIA hub holding one of them; C finds a captive VIA hub below that, with
        // the Ethernet and card reader and two of the dock's own USB ports on it (`Fixtures/AnkerPrimeTB5.json`).
        // G stays off: the VIA hub and the 12 Mb/s function both sit on the root hub's ports.
        Identity(vendorID: 0x291A, productID: 0x83B5): [
            Identity(vendorID: 0x2109, productID: 0x0822),
            Identity(vendorID: 0x2109, productID: 0x2822),
            Identity(vendorID: 0x0BDA, productID: 0x8156),
            Identity(vendorID: 0x05E3, productID: 0x0764),
            Identity(vendorID: 0x291A, productID: 0x83B5),
        ],
        // Dell U4025QW: behind the Thunderbolt chip's own hub (8087:0B40, rule A), a
        // Realtek 4-port hub with two more Realtek hubs and the 2.5G Ethernet on its
        // captive ports, all sharing one container ID (`Fixtures/DellU4025QW.json`).
        Identity(vendorID: 0x413C, productID: 0xC402): [
            Identity(vendorID: 0x0BDA, productID: 0x0483),
            Identity(vendorID: 0x0BDA, productID: 0x5483),
            Identity(vendorID: 0x0BDA, productID: 0x8156),
        ],
    ]

    /// The catalogue entry for the dock or display `dock`, when it has one.
    static func catalogueEntry(for dock: DeviceNode, evidence: Evidence) -> Set<Identity>? {
        dock.registryID.flatMap { evidence.identities[$0] }.flatMap { catalogue[$0] }
    }

    /// Rule G applies: exactly one device listed in `parts` sits on the root hub's ports.
    static func appliesG(_ parts: Set<Identity>, root: DeviceNode) -> Bool {
        root.children.filter { isListed($0, parts) }.count == 1
    }

    /// The device's own vendor and product IDs are in `parts`.
    static func isListed(_ node: DeviceNode, _ parts: Set<Identity>) -> Bool {
        guard node.bus == .usb, let vendor = node.vendorID, let product = node.productID else { return false }
        return parts.contains(Identity(vendorID: vendor, productID: product))
    }

    /// Rule G for `child` of the part `parent`.
    static func isCataloguePart(_ child: DeviceNode, parent: DeviceNode, parentRule: Rule, parts: Set<Identity>,
                                evidence: Evidence) -> Bool {
        guard isListed(child, parts) else { return false }
        if parentRule == .tunnelRoot { return true }
        guard parentRule == .catalogue, isCaptive(child, evidence) else { return false }
        let own = containers(of: child, evidence)
        let parents = Set(containers(of: parent, evidence))
        return own.isEmpty || parents.isEmpty || own.allSatisfy(parents.contains)
    }
}
