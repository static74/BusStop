import BusStopCore
import SwiftUI

/// Layout constants for device rows.
public enum DeviceRowMetrics {
    /// Horizontal step per tree level.
    public static let indent: CGFloat = 16
    /// Width reserved for the disclosure chevron.
    public static let chevronWidth: CGFloat = 14
    /// Where the guide line sits inside one indent step.
    public static let guideOffset: CGFloat = 6
}

/// One device in a port's tree: chevron, icon, name with a caption, speed
/// chip and allocated power. Draws thin turquoise indentation guides for
/// nested devices. A departing device is shown dimmed with "Disconnected".
public struct DeviceRowView: View {
    public var device: DeviceNode
    public var depth: Int
    /// The port the device hangs off; nil for unattributed devices.
    public var port: PhysicalPort?
    public var isExpanded: Bool = true
    /// Set for devices with children; toggles their visibility.
    public var onToggle: (() -> Void)?
    public var isDeparting: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast

    public init(device: DeviceNode, depth: Int, port: PhysicalPort?, isExpanded: Bool = true,
                onToggle: (() -> Void)? = nil, isDeparting: Bool = false) {
        self.device = device
        self.depth = depth
        self.port = port
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.isDeparting = isDeparting
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            chevron
            DeviceIcon(kind: device.kind, size: 22, dimmed: isDeparting)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .lagoonFont(.callout, weight: .medium)
                    .foregroundStyle(isDeparting ? Lagoon.textTertiary : Lagoon.textPrimary)
                    .strikethrough(isDeparting, color: Lagoon.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let caption {
                    Text(caption)
                        .lagoonFont(.caption, monospacedDigits: true)
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
                        .fixedSize()
                }
                if let milliwatts = device.power?.allocatedMilliwatts, milliwatts > 0 {
                    Text(Format.power(milliwatts: milliwatts))
                        .lagoonFont(.caption, monospacedDigits: true)
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

    /// At most two of: roll-up ("3 devices · 7.5 W", or the count and
    /// "Self-powered" for a hub with its own supply), vendor; or "Disconnected". Two keep the line
    /// from truncating in the popover's nested rows; the inspector has the rest.
    private var caption: String? {
        if isDeparting { return "Disconnected" }
        var parts: [String] = []
        if device.power?.isSelfPowered == true {
            // Its own supply powers what is behind it, so the watts add nothing.
            if !device.children.isEmpty {
                parts.append(PopoverText.count(device.descendantCount, "device", "devices"))
            }
            parts.append("Self-powered")
        } else if let rollUp = PopoverText.rollUp(for: device) {
            parts.append(rollUp)
        }
        if let vendor = device.vendorName, !vendor.isEmpty, vendor != device.name {
            parts.append(vendor)
        }
        if parts.isEmpty, device.isTunneled {
            parts.append("Through Thunderbolt")
        }
        return parts.isEmpty ? nil : parts.prefix(2).joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var chevron: some View {
        if let onToggle, !device.children.isEmpty {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .lagoonFont(size: 10, weight: .bold)
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

/// Insert and remove motion for device rows (docs/SPEC.md §4.5).
public enum DeviceRowTransition {
    public static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)

    /// Fade and slide 8 pt on insert, fade on removal; fade only under
    /// Reduce Motion.
    public static func make(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -8)),
            removal: .opacity
        )
    }
}
