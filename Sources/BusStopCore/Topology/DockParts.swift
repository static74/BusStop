import Foundation

/// Folds the USB parts built into a Thunderbolt dock (its USB root hub, its
/// internal hubs and its own USB functions) out of the device tree and into
/// the dock's `internalParts`, so the map draws only devices joined to the
/// dock by real cables (SPEC §5.4 "Built-in dock parts").
///
/// The rules work top-down from the dock: a USB device can be built in only
/// when what it hangs off is the dock's root hub or another built-in part,
/// so nothing behind an external hub is ever hidden. Every rule fails
/// closed: when a key is missing or has the wrong type, or two candidates
/// match where one is expected, the device stays on the map. A built-in part
/// left on the map costs one extra card; a wrong fold would hide a cable.
///
/// - A. Root hub: a USB hub straight below the dock, on the Mac's own USB
///   controller and marked `UsbTunnel`, when it is the only `UsbTunnel` root
///   on the port and the dock is the port's only switch with a live USB
///   tunnel. Its merged USB 2 half goes with it.
/// - B. Identity: a USB device whose `idVendor` / `idProduct` equal the dock
///   switch's `Device Vendor ID` / `Device Model ID` (the dock's own IDs, not
///   the switch chip's), when no other switch has the same pair.
/// - C. Captive: a hub or billboard on a captive port (`USBPortType` 1, on
///   both halves of a merged hub) of a hub folded by C or D. Not on the root
///   hub's own ports, whose flags are not reliable.
/// - D. Identity holder: a hub with a B device on a captive port. When more
///   than one hub in the dock qualifies, B and D are both off.
/// - E. A device that is not a hub, on a hub folded by C.
///
/// What hangs off a part and matches no rule moves up to the dock with its
/// subtree, and its `internalParentID` names the part.
enum DockParts {
    /// Why a part is built in. The rules for a device depend on its parent's.
    enum Rule {
        case tunnelRoot
        case identity
        case captive
        case identityHolder
        case captiveFunction
    }

    /// A device's own USB vendor and product IDs.
    struct Identity: Hashable {
        var vendorID: Int
        var productID: Int
    }

    /// What the rules read from the raw capture, by registry ID.
    struct Evidence {
        /// `USBPortType` of each USB device: 1 is a captive port.
        var portTypes: [UInt64: Int] = [:]
        /// USB devices marked `UsbTunnel`.
        var tunnelled: Set<UInt64> = []
        /// `UsbTunnel` devices on the Mac's own USB controller.
        var hostTunnelled: Set<UInt64> = []
        /// USB devices whose interfaces are all billboard (class 0x11).
        var billboards: Set<UInt64> = []
        /// SuperSpeed half → USB 2 half of each merged hub.
        var companions: [UInt64: UInt64] = [:]
        /// Thunderbolt switch → its device's own IDs, when both are valid
        /// and no other switch reports the same pair.
        var identities: [UInt64: Identity] = [:]
        /// Downstream switches with a live USB tunnel.
        var usbTunnelSwitchIDs: Set<UInt64> = []

        init(raw: RawSnapshot, companions: [UInt64: UInt64], usbTunnelSwitchIDs: Set<UInt64>) {
            self.companions = companions
            self.usbTunnelSwitchIDs = usbTunnelSwitchIDs
            let devices = Dictionary(raw.usbDevices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, device) in devices {
                let p = device.node.properties
                if let type = p.int("USBPortType") { portTypes[id] = type }
                if p.bool("UsbTunnel") == true {
                    tunnelled.insert(id)
                    if DockParts.isHostController(device.ancestry) { hostTunnelled.insert(id) }
                }
                if !device.interfaces.isEmpty,
                   device.interfaces.allSatisfy({ $0.interfaceClass == DeviceClassifier.USBClass.billboard }) {
                    billboards.insert(id)
                }
            }

            let switches = Dictionary(raw.thunderboltSwitches.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
            var found: [UInt64: Identity] = [:]
            var counts: [Identity: Int] = [:]
            for (id, sw) in switches {
                let p = sw.node.properties
                guard let vendor = p.int("Device Vendor ID"), let model = p.int("Device Model ID"),
                      (1...0xFFFF).contains(vendor), (1...0xFFFF).contains(model) else { continue }
                let identity = Identity(vendorID: vendor, productID: model)
                found[id] = identity
                counts[identity, default: 0] += 1
            }
            identities = found.filter { counts[$0.value] == 1 }
        }
    }

    /// `devices` (the trees on one port) with the built-in parts of its dock
    /// folded, or unchanged when no dock qualifies.
    static func fold(_ devices: [DeviceNode], evidence: Evidence) -> [DeviceNode] {
        let all = devices.flatMap { $0.flattened().map(\.device) }
        let tunnelSwitches = all.filter { device in
            device.bus == .thunderbolt && device.registryID.map(evidence.usbTunnelSwitchIDs.contains) == true
        }
        guard tunnelSwitches.count == 1, let dockID = tunnelSwitches[0].registryID else { return devices }

        // USB devices marked `UsbTunnel` that hang off no other USB device.
        var tunnelRoots: [DeviceNode] = []
        func collect(_ node: DeviceNode, parentIsUSB: Bool) {
            if node.bus == .usb, !parentIsUSB, node.registryID.map(evidence.tunnelled.contains) == true {
                tunnelRoots.append(node)
            }
            for child in node.children { collect(child, parentIsUSB: node.bus == .usb) }
        }
        for device in devices { collect(device, parentIsUSB: false) }
        guard tunnelRoots.count == 1, isHub(tunnelRoots[0]), let rootID = tunnelRoots[0].registryID,
              evidence.hostTunnelled.contains(rootID) else { return devices }

        // By registry ID, which is unique among USB devices: a device ID can
        // repeat, and another hub with the same one must not be taken for the root.
        return devices.map { head in
            guard head.bus == .thunderbolt, head.kind == .dock, head.registryID == dockID,
                  let rootIndex = head.children.firstIndex(where: { $0.bus == .usb && $0.registryID == rootID })
            else { return head }
            return folding(head, rootIndex: rootIndex, evidence: evidence)
        }
    }

    /// The dock with the part at `rootIndex` among its children, and every
    /// part below it, folded.
    static func folding(_ dock: DeviceNode, rootIndex: Int, evidence: Evidence) -> DeviceNode {
        var identity = dock.registryID.flatMap { evidence.identities[$0] }
        if let known = identity {
            let holders = dock.flattened().map(\.device).filter { isHub($0) && holdsIdentity($0, known, evidence) }
            if holders.count > 1 { identity = nil }
        }

        var parts: [DeviceNode] = []
        var children: [DeviceNode] = []
        func absorb(_ node: DeviceNode, rule: Rule, parentPartID: String?) {
            var part = node
            part.children = []
            part.internalParentID = parentPartID
            parts.append(part)
            for child in node.children {
                if let childRule = self.rule(for: child, parent: node, parentRule: rule, identity: identity,
                                             evidence: evidence) {
                    absorb(child, rule: childRule, parentPartID: node.id)
                } else {
                    var moved = child
                    moved.internalParentID = node.id
                    children.append(moved)
                }
            }
        }
        for (index, child) in dock.children.enumerated() {
            if index == rootIndex {
                absorb(child, rule: .tunnelRoot, parentPartID: nil)
            } else {
                children.append(child)
            }
        }

        var folded = dock
        folded.children = children
        folded.internalParts = parts.sorted { TopologyBuilder.deviceNameOrder($0.name, $0.id, $1.name, $1.id) }
        return folded
    }

    /// The rule that makes `child` of the built-in part `parent` built in
    /// too, or nil when it stays on the map.
    static func rule(for child: DeviceNode, parent: DeviceNode, parentRule: Rule, identity: Identity?,
                     evidence: Evidence) -> Rule? {
        guard child.bus == .usb, child.registryID != nil else { return nil }
        if let identity, matches(child, identity) { return .identity }
        if let identity, isHub(child), holdsIdentity(child, identity, evidence) { return .identityHolder }
        guard isHub(parent) else { return nil }
        if parentRule == .captive || parentRule == .identityHolder,
           isHub(child) || isBillboard(child, evidence), isCaptive(child, evidence) {
            return .captive
        }
        if parentRule == .captive, !isHub(child) { return .captiveFunction }
        return nil
    }

    // MARK: - Pieces

    /// True below the Mac's own USB controller (`AppleT…USBXHCI`), not one
    /// that a dock or display brings along.
    static func isHostController(_ ancestry: [RawAncestor]) -> Bool {
        guard !USBTreeBuilder.hasTunnelAncestry(ancestry) else { return false }
        return ancestry.contains { ancestor in
            ancestor.className.hasPrefix("AppleT") && ancestor.className.contains("USBXHCI")
                && !ancestor.className.contains("AUSS")
        }
    }

    static func isHub(_ node: DeviceNode) -> Bool {
        node.bus == .usb && node.deviceClass == DeviceClassifier.USBClass.hub
    }

    /// A billboard device (class 0x11, or only billboard interfaces), which
    /// reports the state of USB-C alternate modes.
    static func isBillboard(_ node: DeviceNode, _ evidence: Evidence) -> Bool {
        node.deviceClass == DeviceClassifier.USBClass.billboard
            || node.registryID.map(evidence.billboards.contains) == true
    }

    static func matches(_ node: DeviceNode, _ identity: Identity) -> Bool {
        node.bus == .usb && node.vendorID == identity.vendorID && node.productID == identity.productID
    }

    /// On a captive port: `USBPortType` 1, on the USB 2 half of a merged hub
    /// as well when there is one.
    static func isCaptive(_ node: DeviceNode, _ evidence: Evidence) -> Bool {
        guard let id = node.registryID, evidence.portTypes[id] == 1 else { return false }
        guard let companion = evidence.companions[id] else { return true }
        return evidence.portTypes[companion] == 1
    }

    /// A hub with a device of the dock's own IDs on a captive port.
    static func holdsIdentity(_ hub: DeviceNode, _ identity: Identity, _ evidence: Evidence) -> Bool {
        hub.children.contains { child in
            matches(child, identity) && child.registryID.flatMap { evidence.portTypes[$0] } == 1
        }
    }
}
