import BusStopCore
import SwiftUI

/// The Mac Outline page: a header, the outline of the Mac with each port
/// where it sits, the captions, and the shared Data/Power picker with legends
/// over the bottom edge, as on the map.
struct MacSilhouettePage: View {
    var store: PortStore
    var searchText: String
    var onSelect: (StoreSelection) -> Void
    @AppStorage(TopologyWindowDefaults.linkMode) private var linkMode: GraphLinkMode = .data

    var body: some View {
        let snapshot = store.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WindowDetailHeader(
                    title: "Mac Outline",
                    subtitle: "\(snapshot.machine.name) · \(WindowText.count(snapshot.ports.count, "port", "ports"))")
                MacSilhouetteView(
                    snapshot: snapshot,
                    selectedPort: store.selection.flatMap { TopologyWindowView.owningPort(of: $0, in: snapshot) },
                    mode: linkMode,
                    searchText: searchText,
                    onSelect: { onSelect(.port($0)) })
            }
            .padding(24)
            // Room for the controls laid over the bottom edge.
            // shortcut: fixed reserve, measure the bar if Extra Large text overlaps it.
            .padding(.bottom, 64)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // An overlay, so the fixed-size picker sets no width for the page.
        .overlay(alignment: .bottom) { controls }
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 12) {
            GraphLinkModePicker(linkMode: $linkMode)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    // Their spoken text describes the map's glows and pulses.
                    switch linkMode {
                    case .data: GraphSpeedLegend().accessibilityHidden(true)
                    case .power: GraphPowerLegend().accessibilityHidden(true)
                    }
                    SilhouetteStateLegend(mode: linkMode)
                }
                SilhouetteStateLegend(mode: linkMode)
                Color.clear.frame(width: 0, height: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// The outline itself, with no store dependency, so the host inspector or an
/// "Identify this port" flow can reuse it. Draws every port in
/// `snapshot.ports`, empty ones too, even when "Hide empty ports" is on: an
/// outline with holes would be wrong.
struct MacSilhouetteView: View {
    var snapshot: HostSnapshot
    var selectedPort: PortKey?
    var mode: GraphLinkMode
    var searchText: String
    var onSelect: (PortKey) -> Void

    var body: some View {
        let layout = ChassisLayout.resolve(machine: snapshot.machine, ports: snapshot.ports)
        let faces = Self.faces(for: layout)
        // A live port on a face this family does not draw is listed instead.
        let hidden = layout.slots.filter { !faces.contains($0.face) }.compactMap(\.portKey)
        let unplaced = (layout.unplaced + hidden).compactMap { snapshot.port($0) }
        VStack(alignment: .leading, spacing: 18) {
            if layout.family == .laptop {
                face(nil, layout: layout, caption: "Seen from above, hinge at the top")
            } else if faces.isEmpty {
                face(.front, layout: layout, caption: nil)
            } else {
                ForEach(faces, id: \.self) { side in
                    face(side, layout: layout, caption: side == .rear ? "Back, seen from behind" : "Front")
                }
            }
            if !unplaced.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Not placed")
                        .lagoonFont(.headline, weight: .semibold)
                        .foregroundStyle(Lagoon.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(unplaced) { port in
                        portButton(port) {
                            HStack(spacing: 8) {
                                marked(port, connector: port.kind.catalogConnector, vertical: false)
                                Text(port.label.title)
                                    .lineLimit(1)
                                    .foregroundStyle(Lagoon.textPrimary)
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Positions are approximate. They come from the PortScope port catalogue.")
                if layout.slots.isEmpty {
                    Text("Bus Stop does not know where this Mac's ports are. CONTRIBUTING.md in the project explains how to add it to the catalogue.")
                } else if PortLocationCatalog.entry(for: snapshot.machine.model) == nil {
                    Text("Ports are placed by kind only (rear or front); this Mac is not in the catalogue yet.")
                }
            }
            .lagoonFont(.caption)
            .foregroundStyle(Lagoon.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The faces drawn: a laptop's two sides, or a desktop's front and rear
    /// that have slots (an iMac's ports are all on its back).
    static func faces(for layout: ChassisLayout) -> [ChassisFace] {
        if layout.family == .laptop { return [.left, .right] }
        return [ChassisFace.front, .rear].filter { side in layout.slots.contains { $0.face == side } }
    }

    /// One outline (the laptop from above, or one desktop face) with its slots.
    private func face(_ side: ChassisFace?, layout: ChassisLayout, caption: String?) -> some View {
        let shape = ChassisShape(family: layout.family)
        let slots = layout.slots.filter { side == nil ? ($0.face == .left || $0.face == .right) : $0.face == side }
        let minWidth = shape.minWidth(for: slots)
        let outline = shape
            .stroke(Lagoon.strokeStrong, lineWidth: 1.5)
            .background(shape.fill(Lagoon.surface))
            .contentShape(shape)
            // Help on the body too, so a pointer resting on it does not
            // leave the page's tooltip tracker idle (docs/decisions.md,
            // "The map's controls get their own hosting views").
            .help(snapshot.machine.name)
            .overlay {
                GeometryReader { proxy in
                    ForEach(slots, id: \.self) { slot in
                        glyph(slot)
                            .position(shape.point(for: slot, in: CGRect(origin: .zero, size: proxy.size)))
                    }
                }
            }
        return VStack(alignment: .leading, spacing: 6) {
            if let caption {
                Text(caption)
                    .lagoonFont(.caption, weight: .medium)
                    .foregroundStyle(Lagoon.textSecondary)
            }
            // Too narrow a column scrolls the outline sideways rather than
            // pushing its port buttons on top of each other.
            ViewThatFits(in: .horizontal) {
                outline
                    .aspectRatio(shape.aspectRatio, contentMode: .fit)
                    .frame(minWidth: minWidth, idealWidth: minWidth, maxWidth: max(shape.maxWidth, minWidth))
                ScrollView(.horizontal) {
                    outline.frame(width: minWidth, height: minWidth / shape.aspectRatio)
                }
            }
        }
    }

    @ViewBuilder
    private func glyph(_ slot: ChassisSlot) -> some View {
        let vertical = slot.face == .left || slot.face == .right
        if let key = slot.portKey, let port = snapshot.port(key) {
            portButton(port) {
                marked(port, connector: slot.connector, vertical: vertical).padding(4)
            }
        } else {
            // A connector macOS does not report: drawn, but nothing to act on.
            SilhouetteConnector(connector: slot.connector, vertical: vertical, fill: nil)
                .padding(7)
                .contentShape(Rectangle())
                .help("\(slot.location): \(Self.connectorName(slot.connector)), not reported by macOS")
                .accessibilityHidden(true)
        }
    }

    /// The port's connector with its selection ring and diagnostic dot.
    private func marked(_ port: PhysicalPort, connector: String, vertical: Bool) -> some View {
        SilhouetteConnector(connector: connector, vertical: vertical,
                            fill: SilhouettePaint.paint(for: port, mode: mode).color)
            .padding(3)
            .overlay {
                if port.key == selectedPort {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Lagoon.accent, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let severity = snapshot.worstSeverity(on: port.key) {
                    Circle()
                        .fill(Lagoon.severityColor(severity))
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -4)
                }
            }
    }

    /// A port's button, on the outline or under "Not placed". The tooltip and
    /// spoken label name a diagnostic, since its dot is only a colour.
    private func portButton(_ port: PhysicalPort, @ViewBuilder label: () -> some View) -> some View {
        let note = snapshot.worstSeverity(on: port.key).map { ", diagnostic: \(Lagoon.severityName($0))" } ?? ""
        return Button { onSelect(port.key) } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .opacity(Self.matches(port, in: snapshot, query: searchText) ? 1 : 0.35)
            .help(Self.help(port, in: snapshot) + note)
            .accessibilityLabel(WindowText.portAccessibility(port) + note)
            .accessibilityAddTraits(port.key == selectedPort ? .isSelected : [])
    }

    /// Whether a port stays bright while searching: the port, a device under
    /// it, or a display on it matches.
    static func matches(_ port: PhysicalPort, in snapshot: HostSnapshot, query searchText: String) -> Bool {
        let query = TopologySearch.normalized(searchText)
        return TopologySearch.port(port, matches: query)
            || port.devices.contains { TopologySearch.prune($0, query: query) != nil }
            // A monitor macOS lists only as a display, such as one on HDMI.
            || snapshot.displays.contains { $0.portKey == port.key && TopologySearch.display($0, matches: query) }
    }

    /// "Left Front: Studio Display XDR · 80 Gb/s · 15 W", or "…: empty".
    static func help(_ port: PhysicalPort, in snapshot: HostSnapshot) -> String {
        guard port.isConnected else { return "\(port.label.title): empty" }
        var parts = [port.devices.first?.name
            ?? snapshot.displays.first { $0.portKey == port.key }?.name
            ?? port.charger?.displayName ?? "connected"]
        if let rate = port.link?.rateLabel { parts.append(rate) }
        if let power = WindowText.portPower(port) {
            parts.append((power.isMeasured ? "" : "≤") + Format.power(milliwatts: power.milliwatts))
        }
        return "\(port.label.title): " + parts.joined(separator: " · ")
    }

    static func connectorName(_ connector: String) -> String {
        switch connector {
        case "ethernet": return "Ethernet"
        case "ac-power": return "power inlet"
        case "sd": return "SD card slot"
        case "hdmi": return "HDMI"
        case "magsafe": return "MagSafe"
        case "usb-a": return "USB-A"
        default: return connector.uppercased()
        }
    }
}

/// What one port's glyph shows. Tests compare these cases rather than
/// colours, which may become dynamic.
enum SilhouettePaint: Equatable {
    case empty
    case link(SpeedTier)
    /// Connected with no data rate, such as HDMI or DisplayPort.
    case noRate
    /// Only a charger is plugged in.
    case charger
    case power(PowerTier)

    static func paint(for port: PhysicalPort, mode: GraphLinkMode) -> SilhouettePaint {
        guard port.isConnected else { return .empty }
        switch mode {
        case .power:
            return .power(PowerTier(milliwatts: WindowText.portPower(port)?.milliwatts ?? 0))
        case .data:
            // `LinkInfo.tier` calls an unknown rate USB 2, so check the rate first.
            if let link = port.link, link.bitsPerSecond != nil { return .link(link.tier) }
            if port.charger != nil, port.devices.isEmpty { return .charger }
            return .noRate
        }
    }

    var color: Color {
        switch self {
        case .empty: return Lagoon.textTertiary
        case .link(let tier): return Lagoon.linkColor(tier)
        case .noRate: return Lagoon.accent
        case .charger: return Lagoon.powerIn
        case .power(let tier): return Lagoon.powerColor(tier)
        }
    }
}

/// A connector's opening, roughly to scale: a USB-C capsule, a wider USB-A
/// or HDMI slot, a thin SD slot. Filled with the port's colour, or only
/// outlined for a connector macOS does not report.
struct SilhouetteConnector: View {
    var connector: String
    /// Along a laptop's side, the opening runs top to bottom.
    var vertical: Bool
    var fill: Color?

    var body: some View {
        let (long, short, radius) = Self.size(connector)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if let fill {
                shape.fill(fill)
            } else {
                shape.stroke(Lagoon.textTertiary, lineWidth: 1.2)
            }
        }
        .frame(width: vertical ? short : long, height: vertical ? long : short)
    }

    static func size(_ connector: String) -> (long: CGFloat, short: CGFloat, radius: CGFloat) {
        switch connector {
        case "usb-a": return (24, 10, 2)
        case "hdmi": return (26, 10, 3)
        case "magsafe": return (26, 7, 3.5)
        case "sd": return (28, 5, 2)
        case "ethernet": return (18, 15, 2)
        case "ac-power": return (16, 16, 8)
        default: return (24, 8, 4)
        }
    }
}

/// A generic outline of the Mac, drawn as paths at its final size (no
/// drawing group, no scale effect). A laptop is seen from above with the
/// hinge at the top, so "Left" is the user's left. Desktop faces are seen
/// straight on; the rear face as someone standing behind the Mac sees it.
nonisolated struct ChassisShape: Shape {
    var family: ChassisFamily

    /// Width over height of the drawn frame.
    var aspectRatio: CGFloat {
        switch family {
        case .laptop: return 1.45
        case .macMini: return 2.6
        case .macStudio: return 2.0
        case .macPro: return 0.85
        case .iMac: return 1.2
        case .other: return 2.4
        }
    }

    var maxWidth: CGFloat {
        switch family {
        case .laptop: return 440
        case .macPro: return 260
        case .iMac: return 380
        default: return 460
        }
    }

    /// Room left and right of the body so glyphs on its edge stay inside.
    private static let sideInset: CGFloat = 14

    /// Centre to centre, room for the widest port button: a 28 pt connector
    /// and 14 pt of padding that takes clicks.
    static let slotSpacing: CGFloat = 42

    /// The narrowest frame that keeps `slots` (one desktop face, or a
    /// laptop's two sides) `slotSpacing` apart. Slots are spread evenly, so
    /// n slots on a face need n + 1 steps along it.
    func minWidth(for slots: [ChassisSlot]) -> CGFloat {
        let perFace = Dictionary(grouping: slots, by: \.face).values.map(\.count).max() ?? 0
        let length = CGFloat(perFace + 1) * Self.slotSpacing
        // A laptop's sides run along the body's height, which is the frame's less 4 pt.
        return family == .laptop ? (length + 4) * aspectRatio : length + 2 * Self.sideInset
    }

    private func body(in rect: CGRect) -> CGRect {
        let inset = rect.insetBy(dx: Self.sideInset, dy: 2)
        // An iMac's display sits on a stand that takes the bottom fifth.
        return family == .iMac ? CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height * 0.8)
            : inset
    }

    /// Where a slot's glyph goes in `rect`: along the laptop's sides from
    /// rear (top) to front (bottom), or along a row across a desktop face.
    func point(for slot: ChassisSlot, in rect: CGRect) -> CGPoint {
        let body = body(in: rect)
        switch slot.face {
        case .left: return CGPoint(x: body.minX, y: body.minY + body.height * slot.position)
        case .right: return CGPoint(x: body.maxX, y: body.minY + body.height * slot.position)
        case .front, .rear:
            let row: CGFloat
            switch family {
            case .macPro: row = slot.face == .front ? 0.1 : 0.5
            case .iMac: row = 0.85
            default: row = 0.55
            }
            return CGPoint(x: body.minX + body.width * slot.position, y: body.minY + body.height * row)
        }
    }

    func path(in rect: CGRect) -> Path {
        let body = body(in: rect)
        var path = Path()
        switch family {
        case .laptop:
            path.addRoundedRect(in: body, cornerSize: CGSize(width: 14, height: 14), style: .continuous)
            // Keyboard toward the hinge, trackpad toward the front.
            let keys = CGRect(x: body.minX + body.width * 0.1, y: body.minY + body.height * 0.1,
                              width: body.width * 0.8, height: body.height * 0.42)
            path.addRoundedRect(in: keys, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
            let pad = CGRect(x: body.midX - body.width * 0.2, y: body.minY + body.height * 0.6,
                             width: body.width * 0.4, height: body.height * 0.3)
            path.addRoundedRect(in: pad, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
        case .iMac:
            path.addRoundedRect(in: body, cornerSize: CGSize(width: 12, height: 12), style: .continuous)
            let stand = CGRect(x: body.midX - body.width * 0.14, y: body.maxY, width: body.width * 0.28,
                               height: rect.maxY - 2 - body.maxY)
            path.addRect(stand)
        case .macPro:
            path.addRoundedRect(in: body, cornerSize: CGSize(width: 10, height: 10), style: .continuous)
            // Handles on top.
            for x in [0.2, 0.7] {
                path.addRoundedRect(in: CGRect(x: body.minX + body.width * x, y: body.minY + 2,
                                               width: body.width * 0.1, height: 4),
                                    cornerSize: CGSize(width: 2, height: 2))
            }
        case .macMini, .macStudio, .other:
            path.addRoundedRect(in: body, cornerSize: CGSize(width: body.height * 0.12, height: body.height * 0.12),
                                style: .continuous)
        }
        return path
    }
}

/// Key for the outline's own colours: empty ports, and in Data mode
/// connected ports with no data rate and charger-only ports.
struct SilhouetteStateLegend: View {
    var mode: GraphLinkMode
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let swatches: [(String, SilhouettePaint)] = mode == .data
            ? [("Empty", .empty), ("No rate", .noRate), ("Charger", .charger)]
            : [("Empty", .empty)]
        HStack(spacing: 12) {
            ForEach(swatches, id: \.0) { title, paint in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(paint.color)
                        .frame(width: 16, height: 6)
                    Text(title)
                        .lagoonFont(.caption2, weight: .medium)
                        .foregroundStyle(Lagoon.textSecondary)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Lagoon.surface.opacity(0.94)))
        .overlay(Capsule().strokeBorder(WindowContrast.stroke(contrast), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == .data
            ? "Port colours: dim for empty, the link colour for its speed, accent when connected with no data rate, power colour for a charger"
            : "Port colours by power: dim for empty, then deep red, orange, amber and gold as watts rise")
    }
}
