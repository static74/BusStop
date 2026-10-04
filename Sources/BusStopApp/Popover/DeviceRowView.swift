import BusStopCore
import SwiftUI

/// Layout constants for device rows.
enum DeviceRowMetrics {
    /// Horizontal step per tree level.
    static let indent: CGFloat = 16
    /// Width reserved for the disclosure chevron.
    static let chevronWidth: CGFloat = 14
    /// Where the guide line sits inside one indent step.
    static let guideOffset: CGFloat = 6
}

/// One device in a port's tree: chevron, icon, name with a caption, speed
/// chip and allocated power. Draws thin turquoise indentation guides for
/// nested devices. A departing device is shown dimmed with "Disconnected".
struct DeviceRowView: View {
    var device: DeviceNode
    var depth: Int
    /// The port the device hangs off; nil for unattributed devices.
    var port: PhysicalPort?
    var isExpanded: Bool = true
    /// Set for devices with children; toggles their visibility.
    var onToggle: (() -> Void)?
    var isDeparting: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            chevron
            DeviceIcon(kind: device.kind, size: 22, dimmed: isDeparting)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isDeparting ? Lagoon.textTertiary : Lagoon.textPrimary)
                    .strikethrough(isDeparting, color: Lagoon.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            if !isDeparting {
                if let link = device.link {
                    SpeedChip(link: link)
                }
                if let milliwatts = device.power?.allocatedMilliwatts, milliwatts > 0 {
                    Text(Format.power(milliwatts: milliwatts))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help(device.power?.source == .usbAllocation ? "Power allocated by USB" : "Power")
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, CGFloat(depth) * DeviceRowMetrics.indent)
        .background(alignment: .leading) {
            IndentGuides(depth: depth, isStrong: contrast == .increased)
        }
        .opacity(isDeparting ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PopoverText.deviceAccessibilityLabel(device, port: port, depth: depth,
                                                                 isDeparting: isDeparting))
        .accessibilityValue(Text(onToggle == nil ? "" : (isExpanded ? "Expanded" : "Collapsed")))
        .accessibilityActions {
            if let onToggle {
                Button(isExpanded ? "Collapse" : "Expand", action: onToggle)
            }
        }
    }

    /// Vendor, roll-up ("3 devices · 7.5 W"), "Self-powered" or "Disconnected".
    private var caption: String? {
        if isDeparting { return "Disconnected" }
        var parts: [String] = []
        if let vendor = device.vendorName, !vendor.isEmpty, vendor != device.name {
            parts.append(vendor)
        }
        if let rollUp = PopoverText.rollUp(for: device) {
            parts.append(rollUp)
        }
        if device.power?.isSelfPowered == true {
            parts.append("Self-powered")
        }
        if parts.isEmpty, device.isTunneled {
            parts.append("Through Thunderbolt")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var chevron: some View {
        if let onToggle, !device.children.isEmpty {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Lagoon.accent.opacity(0.8))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: DeviceRowMetrics.chevronWidth, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
        } else {
            Color.clear.frame(width: DeviceRowMetrics.chevronWidth, height: 1)
        }
    }
}

/// Vertical turquoise hairlines, one per ancestor level.
private struct IndentGuides: View {
    var depth: Int
    var isStrong: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(depth, 0), id: \.self) { _ in
                Rectangle()
                    .fill(Lagoon.accent.opacity(isStrong ? 0.45 : 0.22))
                    .frame(width: 1)
                    .padding(.leading, DeviceRowMetrics.guideOffset)
                    .frame(width: DeviceRowMetrics.indent, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A device and, when expanded, its children, recursively. Containers
/// (hubs, docks, displays with hubs) start expanded.
struct DeviceTreeNode: View {
    var device: DeviceNode
    var depth: Int
    var port: PhysicalPort?

    @State private var isExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeviceRowView(device: device, depth: depth, port: port, isExpanded: isExpanded,
                          onToggle: device.children.isEmpty ? nil : toggle)
                .deviceContextMenu(device: device, port: port)
            if isExpanded {
                ForEach(device.children) { child in
                    DeviceTreeNode(device: child, depth: depth + 1, port: port)
                        .transition(DeviceRowTransition.make(reduceMotion: reduceMotion))
                }
            }
        }
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : DeviceRowTransition.spring) {
            isExpanded.toggle()
        }
    }
}

/// Insert and remove motion for device rows (docs/SPEC.md §4.5).
enum DeviceRowTransition {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)

    /// Fade and slide 8 pt on insert, fade on removal; fade only under
    /// Reduce Motion.
    static func make(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -8)),
            removal: .opacity
        )
    }
}

extension View {
    /// "Show in Topology", "Copy Name", "Copy Details".
    func deviceContextMenu(device: DeviceNode, port: PhysicalPort?) -> some View {
        contextMenu {
            Button("Show in Topology") {
                WindowManager.shared.showTopology(selecting: .device(device.id))
            }
            Divider()
            Button("Copy Name") {
                PopoverText.copyToPasteboard(device.name)
            }
            Button("Copy Details") {
                let redact = AppSettings.shared.redactExports
                PopoverText.copyToPasteboard(PopoverText.details(for: device, port: port, redactSerials: redact))
            }
        }
    }
}
