import Foundation

extension DockParts {
    /// USB parts built into docks and displays whose own flags do not show it
    /// (rule G), by the Thunderbolt switch's `Device Vendor ID` / `Device
    /// Model ID`: the USB vendor and product IDs of those parts.
    ///
    /// A listed device folds only when it is the one listed device on the
    /// root hub's ports, or sits on a captive port of a part this rule folded
    /// and reports no container ID that its parent part does not. A device
    /// on a standard port, such as one a user plugged into the monitor,
    /// stays whatever its IDs.
    ///
    /// Each entry comes from a capture of that model (`busstop --raw`) and
    /// its `kUSBContainerID` grouping; see CONTRIBUTING.md.
    static let catalogue: [Identity: Set<Identity>] = [
        // Dell U4025QW: behind the Thunderbolt chip's own hub (8087:0B40, rule A), a
        // Realtek 4-port hub with two more Realtek hubs and the 2.5G Ethernet on its
        // captive ports, all sharing one container ID (`Fixtures/DellU4025QW.json`).
        Identity(vendorID: 0x413C, productID: 0xC402): [
            Identity(vendorID: 0x0BDA, productID: 0x0483),
            Identity(vendorID: 0x0BDA, productID: 0x5483),
            Identity(vendorID: 0x0BDA, productID: 0x8156),
        ],
    ]

    /// The catalogue entry for the dock or display `dock`, when it has one
    /// and exactly one listed device sits on the root hub's ports.
    static func catalogued(_ dock: DeviceNode, root: DeviceNode, evidence: Evidence) -> Set<Identity>? {
        guard let model = dock.registryID.flatMap({ evidence.identities[$0] }),
              let parts = catalogue[model] else { return nil }
        let listed = root.children.filter { isListed($0, parts) }
        return listed.count == 1 ? parts : nil
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
