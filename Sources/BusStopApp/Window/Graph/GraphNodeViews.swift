import BusStopCore
import SwiftUI

// The cards drawn at each graph node. Cards are solid near-black surfaces with
// a turquoise hairline (SPEC §4.1); the selected node gets a glowing stroke.

/// One graph node: a selectable card positioned by `TopologyGraphView`.
struct GraphNodeView: View {
    var node: GraphNode
    var snapshot: HostSnapshot
    var isSelected: Bool
    var isDimmed: Bool
    var onSelect: () -> Void

    @State private var isHovered = false
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if node.tag != nil {
                Button(action: onSelect) { card }
                    .buttonStyle(GraphNodeButtonStyle())
                    .accessibilityLabel(accessibilityText)
                    .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                    .accessibilityHint("Shows details in the inspector")
            } else {
                card
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText)
            }
        }
        .opacity(isDimmed ? 0.28 : 1)
        .onHover { isHovered = $0 }
        // New nodes fade in and slide 8 pt from their link (SPEC §4.5).
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared || reduceMotion ? 0 : -8)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { hasAppeared = true }
        }
    }

    private var card: some View {
        content
            .frame(width: node.frame.width, height: node.frame.height, alignment: .leading)
            .background(background)
            .overlay(border)
            .shadow(color: isSelected ? Lagoon.accent.opacity(0.45) : .clear, radius: isSelected ? 12 : 0)
            .contentShape(RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch node.content {
        case .host:
            GraphHostCard(snapshot: snapshot)
        case .port(let port):
            GraphPortCard(port: port)
        case .otherGroup(let count):
            GraphOtherCard(count: count)
        case .device(let device, let isDeparting):
            GraphDeviceCard(device: device, isDeparting: isDeparting)
        case .display(let display):
            GraphDisplayCard(display: display)
        }
    }

    private var isHost: Bool {
        if case .host = node.content { return true }
        return false
    }

    private var isDashed: Bool {
        switch node.content {
        case .otherGroup: return true
        case .device(_, let isDeparting): return isDeparting
        default: return false
        }
    }

    private var isEmptyPort: Bool {
        if case .port(let port) = node.content { return !port.isConnected }
        return false
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
        let fill: Color = isHovered || isSelected ? Lagoon.surfaceRaised : (isEmptyPort ? Lagoon.background : Lagoon.surface)
        return shape.fill(fill)
    }

    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
        let color: Color
        if isSelected {
            color = Lagoon.accentGlow
        } else if isHost || isHovered {
            color = Lagoon.strokeStrong
        } else {
            color = Lagoon.stroke
        }
        return shape.strokeBorder(
            color,
            style: StrokeStyle(lineWidth: isSelected ? 1.6 : 1, dash: isDashed && !isSelected ? [4, 3] : [])
        )
    }

    private var accessibilityText: String {
        switch node.content {
        case .host:
            let machine = snapshot.machine
            var parts = [machine.name]
            if let chip = machine.chip { parts.append(chip) }
            parts.append(WindowText.count(snapshot.ports.count, "port", "ports"))
            parts.append(WindowText.count(snapshot.deviceCount, "device", "devices"))
            if let reading = WindowText.hostPower(snapshot.power) {
                let direction = reading.direction == .input ? "in" : "out"
                parts.append("\(WindowText.spokenPower(reading.milliwatts)) \(direction)")
            }
            return parts.joined(separator: ", ")
        case .port(let port):
            return WindowText.portAccessibility(port)
        case .otherGroup(let count):
            return "Other devices, not tied to a port, \(WindowText.count(count, "item", "items"))"
        case .device(let device, let isDeparting):
            let portTitle = node.portKey.flatMap { snapshot.port($0)?.label.title }
            return WindowText.deviceAccessibility(device, portTitle: portTitle, isDeparting: isDeparting)
        case .display(let display):
            var parts = [display.name, "display"]
            if let mode = display.modeDescription { parts.append(mode) }
            if let link = display.link { parts.append("connected at \(WindowText.spokenRate(link))") }
            return parts.joined(separator: ", ")
        }
    }
}

/// Slight press feedback for graph nodes.
struct GraphNodeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Cards

/// The Mac: glyph, name, chip and power summary.
struct GraphHostCard: View {
    var snapshot: HostSnapshot

    var body: some View {
        let machine = snapshot.machine
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: machine.isLaptop ? "laptopcomputer" : "macmini")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Lagoon.accent)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Lagoon.accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Lagoon.accent.opacity(0.35), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.name)
                        .font(Lagoon.titleFont)
                        .foregroundStyle(Lagoon.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(machine.chip ?? machine.model)
                        .font(.caption)
                        .foregroundStyle(Lagoon.textSecondary)
                        .lineLimit(1)
                }
            }
            Rectangle()
                .fill(Lagoon.stroke)
                .frame(height: 1)
            HStack(spacing: 6) {
                if let reading = WindowText.hostPower(snapshot.power) {
                    PowerBadge(milliwatts: reading.milliwatts, direction: reading.direction, isMeasured: reading.isMeasured)
                }
                Spacer(minLength: 0)
                Text(WindowText.count(snapshot.deviceCount, "device", "devices"))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Lagoon.textSecondary)
            }
            Text(snapshot.power.battery?.statusText ?? WindowText.count(snapshot.ports.count, "port", "ports"))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Lagoon.textTertiary)
                .lineLimit(1)
        }
        .padding(14)
    }
}

/// A physical port: connector, name, capability, active transports and power.
struct GraphPortCard: View {
    var port: PhysicalPort

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PortIcon(kind: port.kind, isActive: port.isConnected, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(port.label.title)
                        .font(.system(.callout).weight(.semibold))
                        .foregroundStyle(port.isConnected ? Lagoon.textPrimary : Lagoon.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let reading = WindowText.portPower(port) {
                        PowerBadge(milliwatts: reading.milliwatts, direction: reading.direction, isMeasured: reading.isMeasured)
                            .fixedSize()
                    }
                }
                Text(port.capabilityDescription ?? port.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(port.isConnected ? Lagoon.textSecondary : Lagoon.textTertiary)
                    .lineLimit(1)
                GraphTransportChips(port: port)
            }
        }
        .padding(10)
        .opacity(port.isConnected ? 1 : 0.62)
    }
}

/// Active transport chips, trimmed to what fits.
struct GraphTransportChips: View {
    var port: PhysicalPort

    var body: some View {
        let transports = port.activeTransports
        if !port.isConnected {
            Text("Empty")
                .font(.caption)
                .foregroundStyle(Lagoon.textTertiary)
        } else if transports.isEmpty {
            Text(port.charger != nil ? "Charging" : "Connected")
                .font(Lagoon.chipFont)
                .foregroundStyle(port.charger != nil ? Lagoon.powerIn : Lagoon.textSecondary)
        } else {
            ViewThatFits(in: .horizontal) {
                chips(transports)
                chips(Array(transports.prefix(2)))
                chips(Array(transports.prefix(1)))
            }
        }
    }

    private func chips(_ transports: [TransportInfo]) -> some View {
        HStack(spacing: 4) {
            ForEach(transports, id: \.kind) { transport in
                TransportChip(transport: transport)
                    .fixedSize()
            }
        }
    }
}

/// A device: kind icon, name and a subtitle with kind, power or roll-up.
struct GraphDeviceCard: View {
    var device: DeviceNode
    var isDeparting: Bool

    var body: some View {
        HStack(spacing: 10) {
            DeviceIcon(kind: device.kind, size: 30, dimmed: isDeparting)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(.callout).weight(.semibold))
                    .foregroundStyle(isDeparting ? Lagoon.textTertiary : Lagoon.textPrimary)
                    .lineLimit(1)
                Text(isDeparting ? "Disconnected" : WindowText.deviceSubtitle(device))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isDeparting ? Lagoon.textTertiary : Lagoon.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if device.isTunneled && !isDeparting {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Lagoon.accent.opacity(0.7))
                    .help("Reached through a Thunderbolt / USB4 tunnel")
            }
        }
        .padding(.horizontal, 12)
        .opacity(isDeparting ? 0.55 : 1)
    }
}

/// An external display that is not part of a device tree.
struct GraphDisplayCard: View {
    var display: DisplayInfo

    var body: some View {
        HStack(spacing: 10) {
            DeviceIcon(kind: .display, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(.system(.callout).weight(.semibold))
                    .foregroundStyle(Lagoon.textPrimary)
                    .lineLimit(1)
                Text(display.modeDescription ?? "Display")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }
}

/// Header for devices and displays that could not be tied to a port.
struct GraphOtherCard: View {
    var count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Lagoon.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Lagoon.surfaceRaised)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("Other devices")
                    .font(.system(.callout).weight(.semibold))
                    .foregroundStyle(Lagoon.textPrimary)
                Text("Not tied to a specific port")
                    .font(.caption)
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
                Text(WindowText.count(count, "item", "items"))
                    .font(Lagoon.chipFont)
                    .monospacedDigit()
                    .foregroundStyle(Lagoon.textTertiary)
            }
        }
        .padding(10)
    }
}
