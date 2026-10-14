import BusStopCore
import SwiftUI

// The inspector page for a link clicked in the graph: what the two ends
// negotiated and, for the cable plugged into one of the Mac's own ports, what
// the cable's e-marker chip says it is rated for.

/// The two ends of a link, resolved from the snapshot.
struct LinkEnds {
    enum Parent {
        case mac
        case port(PhysicalPort)
        case device(DeviceNode)
        /// Devices and displays not tied to a port.
        case other
    }

    enum Child {
        case port(PhysicalPort)
        case device(DeviceNode)
        case display(DisplayInfo)
    }

    var parent: Parent
    var child: Child
    /// The Mac's port the link hangs off, when known.
    var port: PhysicalPort?

    /// The link that leads to `child` (a port, device or display), or nil
    /// when the snapshot no longer has it.
    static func resolve(_ child: StoreSelection, in snapshot: HostSnapshot) -> LinkEnds? {
        switch child {
        case .host, .link:
            return nil
        case .port(let key):
            guard let port = snapshot.port(key) else { return nil }
            return LinkEnds(parent: .mac, child: .port(port), port: port)
        case .device(let id):
            guard let device = snapshot.device(id: id) else { return nil }
            if let port = snapshot.port(containing: id) {
                let parent = parentDevice(of: id, in: port.devices).map(Parent.device) ?? .port(port)
                return LinkEnds(parent: parent, child: .device(device), port: port)
            }
            let parent = parentDevice(of: id, in: snapshot.otherDevices).map(Parent.device) ?? .other
            return LinkEnds(parent: parent, child: .device(device), port: nil)
        case .display(let id):
            guard let display = snapshot.displays.first(where: { $0.id == id }) else { return nil }
            if let port = display.portKey.flatMap({ snapshot.port($0) }) {
                // The graph draws it under the port's Thunderbolt dock or
                // display when there is exactly one (see `GraphLayout`).
                let heads = port.devices.filter { $0.bus == .thunderbolt }
                let parent: Parent = heads.count == 1 ? .device(heads[0]) : .port(port)
                return LinkEnds(parent: parent, child: .display(display), port: port)
            }
            return LinkEnds(parent: .other, child: .display(display), port: nil)
        }
    }

    private static func parentDevice(of id: String, in nodes: [DeviceNode]) -> DeviceNode? {
        for node in nodes {
            if node.children.contains(where: { $0.id == id }) { return node }
            if let found = parentDevice(of: id, in: node.children) { return found }
        }
        return nil
    }

    /// True when the link is the cable in one of the Mac's own ports: the
    /// Mac to a port, or a port to what is plugged straight into it. The Mac
    /// can read that cable's e-marker; it cannot read one further along.
    var isCableInMacPort: Bool {
        guard let port, port.kind != .sdCard else { return false }
        switch parent {
        case .mac: return port.isConnected
        case .port: return true
        case .device, .other: return false
        }
    }

    var link: LinkInfo? {
        switch child {
        case .port(let port): return port.link
        case .device(let device): return device.link
        case .display(let display): return display.link
        }
    }

    func parentName(machine: MachineSummary) -> String {
        switch parent {
        case .mac: return machine.name
        case .port(let port): return port.label.title
        case .device(let device): return device.name
        case .other: return "Other devices"
        }
    }

    /// The dock part a device hangs off when the folding of the dock's
    /// built-in parts moved it up to the dock (`DeviceNode.internalParentID`).
    var builtInPart: DeviceNode? {
        guard case .device(let dock) = parent, case .device(let device) = child,
              let partID = device.internalParentID else { return nil }
        return dock.internalParts?.first { $0.id == partID }
    }

    var childName: String {
        switch child {
        case .port(let port): return port.label.title
        case .device(let device): return device.name
        case .display(let display): return display.name
        }
    }
}

/// A link: the negotiated speed, the cable's rating when the Mac can read
/// it, and the power across it.
struct LinkInspector: View {
    var store: PortStore
    var snapshot: HostSnapshot
    var ends: LinkEnds

    var body: some View {
        let parentName = ends.parentName(machine: snapshot.machine)
        InspectorHeader(title: "\(parentName) → \(ends.childName)", subtitle: subtitle) {
            Image(systemName: "cable.connector")
                .lagoonFont(size: 18, weight: .medium)
                .foregroundStyle(Lagoon.accent)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Lagoon.accent.opacity(0.12)))
                .accessibilityHidden(true)
        } accessory: {
            if let link = ends.link { SpeedChip(link: link, compact: false) }
        }

        linkSection
        cableSection(parentName: parentName)
        powerSection
        endsSection(parentName: parentName)
    }

    private var subtitle: String {
        if ends.isCableInMacPort, let port = ends.port { return "Cable in \(port.label.title)" }
        return "Link"
    }

    @ViewBuilder
    private var linkSection: some View {
        if let link = ends.link {
            LinkInspectorSection(link: link, title: "Negotiated link")
        } else {
            InspectorSection(title: "Negotiated link") {
                if case .port(let port) = ends.child, !port.isConnected {
                    LinkInspectorNote(text: "Nothing is plugged into this port.")
                } else {
                    InspectorRow(label: "Speed", value: "Not reported")
                }
            }
        }
    }

    @ViewBuilder
    private func cableSection(parentName: String) -> some View {
        if ends.isCableInMacPort, let port = ends.port {
            InspectorSection(title: "Cable (from its e-marker chip)") {
                if let cable = port.cable {
                    CableInspectorRows(cable: cable)
                    if let note = LinkCableNote.text(link: ends.link, cable: cable, port: port) {
                        LinkInspectorNote(text: note)
                    }
                } else if port.kind == .usbC || port.kind == .thunderbolt {
                    LinkInspectorNote(text: "This cable has no e-marker the Mac can read. Cables without an "
                        + "e-marker are limited to 3 A (60 W), and most carry only USB 2 or 5 Gb/s data.")
                } else {
                    LinkInspectorNote(text: "Only USB-C cables carry an e-marker chip, so the Mac cannot "
                        + "read a rating for the cable in this \(port.kind.displayName) port.")
                }
                if case .device(let device) = ends.child, device.isTunneled {
                    LinkInspectorNote(text: "\(device.name) is reached through a Thunderbolt / USB4 tunnel: "
                        + "this cable carries it together with everything else on \(port.label.title).")
                }
            }
        } else if case .port = ends.child {
            // An empty port: no cable to describe.
            EmptyView()
        } else {
            InspectorSection(title: "Cable") {
                switch ends.parent {
                case .other:
                    LinkInspectorNote(text: "Bus Stop could not tie this to a port, so it cannot tell which "
                        + "cable it uses. Its speed above is what the link negotiated.")
                case .port(let port) where port.kind == .sdCard:
                    LinkInspectorNote(text: "A card in the SD card slot has no cable.")
                default:
                    LinkInspectorNote(text: "This cable is plugged into \(parentName), not into the Mac, so the "
                        + "Mac cannot read its e-marker chip. Its speed above is what the link negotiated.")
                    if let part = ends.builtInPart {
                        LinkInspectorNote(text: "Inside the dock, the port it uses belongs to \(part.name), "
                            + "which is built into \(parentName).")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var powerSection: some View {
        switch ends.child {
        case .port(let port):
            portPowerSection(port)
        case .device(let device):
            // The cable in a Mac port carries the port's power (a dock's
            // charging, say), not just the device's USB allocation.
            if case .port(let port) = ends.parent, WindowText.portPower(port) != nil {
                portPowerSection(port)
            } else if let power = device.power {
                InspectorSection(title: "Power across this link") {
                    InspectorRow(label: "Allocated", value: power.allocatedMilliwatts.map { Format.power(milliwatts: $0) })
                    InspectorRow(label: "Source", value: WindowText.powerSource(power.source))
                    InspectorRow(label: "Self-powered", value: power.isSelfPowered.map { $0 ? "Yes" : "No" })
                    if !device.children.isEmpty {
                        InspectorRow(label: "With devices below", value: Format.power(milliwatts: device.rolledUpMilliwatts))
                    }
                }
            }
        case .display:
            EmptyView()
        }
    }

    @ViewBuilder
    private func portPowerSection(_ port: PhysicalPort) -> some View {
        if let reading = WindowText.portPower(port) {
            InspectorSection(title: "Power across this link") {
                InspectorRow(label: "Power", value: Format.power(milliwatts: reading.milliwatts))
                InspectorRow(label: "Direction", value: WindowText.powerDirection(reading.direction))
                InspectorRow(label: "Measured", value: WindowText.yesNo(reading.isMeasured))
            }
        }
    }

    private func endsSection(parentName: String) -> some View {
        InspectorSection(title: "Ends") {
            switch ends.parent {
            case .mac:
                InspectorLinkRow(systemName: snapshot.machine.isLaptop ? "laptopcomputer" : "macmini",
                                 title: parentName, detail: "Mac") { store.selection = .host }
            case .port(let port):
                InspectorLinkRow(systemName: port.kind.symbolName, title: parentName, detail: "Port") {
                    store.selection = .port(port.key)
                }
            case .device(let device):
                InspectorLinkRow(systemName: device.kind.symbolName, title: parentName, detail: device.kind.displayName) {
                    store.selection = .device(device.id)
                }
            case .other:
                InspectorRow(label: "From", value: parentName)
            }
            switch ends.child {
            case .port(let port):
                InspectorLinkRow(systemName: port.kind.symbolName, title: port.label.title, detail: "Port") {
                    store.selection = .port(port.key)
                }
            case .device(let device):
                InspectorLinkRow(systemName: device.kind.symbolName, title: device.name, detail: device.kind.displayName) {
                    store.selection = .device(device.id)
                }
            case .display(let display):
                InspectorLinkRow(systemName: DeviceKind.display.symbolName, title: display.name, detail: "Display") {
                    store.selection = .display(display.id)
                }
            }
        }
    }
}

/// What a cable's e-marker says about it.
struct CableInspectorRows: View {
    var cable: CableInfo

    var body: some View {
        InspectorRow(label: "Type", value: cable.typeDescription)
        InspectorRow(label: "Rated speed",
                     value: cable.speedDescription ?? cable.maxBitsPerSecond.map { Format.dataRate(bitsPerSecond: $0) })
        InspectorRow(label: "Rated power", value: cable.ratedPowerWatts.map { "\($0) W" })
        InspectorRow(label: "Rated current", value: cable.currentRatingMilliamps.map { Format.current(milliamps: $0) })
        InspectorRow(label: "Maximum voltage", value: cable.maxVoltageMillivolts.map { Format.voltage(millivolts: $0) })
        InspectorRow(label: "Extended Power Range", value: cable.isEPRCapable.map { $0 ? "Yes" : "No" })
        InspectorRow(label: "Active", value: cable.isActive.map { $0 ? "Yes" : "No" })
        InspectorRow(label: "Optical", value: cable.isOptical.map { $0 ? "Yes" : "No" })
        InspectorRow(label: "Power Delivery", value: cable.pdRevision.map(InspectorFormat.pdRevision))
        // E-marker vendor IDs are USB-IF IDs, so the built-in table names them.
        InspectorRow(label: "Vendor", value: cable.vendorID.flatMap(USBVendorCatalog.name(forVendorID:)))
        InspectorRow(label: "Vendor ID", value: cable.vendorID.map(Format.hex4), monospaced: true)
        InspectorRow(label: "Product ID", value: cable.productID.map(Format.hex4), monospaced: true)
    }
}

/// A short explanation inside an inspector section.
struct LinkInspectorNote: View {
    var text: String

    var body: some View {
        Text(text)
            .lagoonFont(.callout)
            .foregroundStyle(Lagoon.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// One plain sentence comparing a link's speed with its cable's rating and
/// the port's capability, when they tell the user something.
enum LinkCableNote {
    /// Rates closer than this are treated as the same.
    private static let margin = 0.9

    static func text(link: LinkInfo?, cable: CableInfo, port: PhysicalPort) -> String? {
        guard let cableRate = cable.maxBitsPerSecond, cableRate > 0 else { return nil }
        // DisplayPort and HDMI rates are not USB data rates; comparing them
        // with the cable's USB rating would mislead.
        if let family = link?.family, family == .displayPort || family == .hdmi { return nil }
        let portRate = portMaxBitsPerSecond(port)
        let cableLabel = Format.dataRate(bitsPerSecond: cableRate)

        if let linkRate = link?.bitsPerSecond, linkRate > 0 {
            let linkLabel = Format.dataRate(bitsPerSecond: linkRate)
            if isBelow(linkRate, cableRate) {
                if let portRate, !isBelow(linkRate, portRate) {
                    return "The link runs at \(linkLabel), the most this port supports. "
                        + "The cable is rated for \(cableLabel)."
                }
                return "The link runs at \(linkLabel); the cable is rated for \(cableLabel), "
                    + "so the device, not the cable, is the limit."
            }
            if let portRate, isBelow(cableRate, portRate), !isBelow(cableRate, linkRate) {
                return "The cable is rated for \(cableLabel), which limits this port: it supports up to "
                    + "\(Format.dataRate(bitsPerSecond: portRate)). A faster cable could give a faster link "
                    + "if the device supports it."
            }
            return nil
        }
        if let portRate, isBelow(cableRate, portRate) {
            return "The cable is rated for \(cableLabel), less than this port supports "
                + "(up to \(Format.dataRate(bitsPerSecond: portRate)))."
        }
        return nil
    }

    /// True when `rate` is clearly below `reference`.
    private static func isBelow(_ rate: Int64, _ reference: Int64) -> Bool {
        Double(rate) < Double(reference) * margin
    }

    /// The fastest data rate the port supports, from its catalogue
    /// capability ("Thunderbolt 5", "USB 3 (10 Gb/s)") or, failing that,
    /// whether it supports Thunderbolt. Nil when unknown.
    static func portMaxBitsPerSecond(_ port: PhysicalPort) -> Int64? {
        let capability = (port.capabilityDescription ?? "").lowercased()
        if capability.contains("thunderbolt 5") || capability.contains("usb4 v2") { return 80_000_000_000 }
        if capability.contains("thunderbolt") || capability.contains("usb4") || capability.contains("usb 4") {
            return 40_000_000_000
        }
        if capability.contains("10 gb/s") { return 10_000_000_000 }
        if capability.contains("5 gb/s") { return 5_000_000_000 }
        if capability.contains("usb 2") { return 480_000_000 }
        return port.supportsThunderbolt ? 40_000_000_000 : nil
    }
}
