import AppKit
import BusStopCore
import SwiftUI

// Building blocks for the inspector: titled groups of key/value rows, a
// header, the port-name editor and the raw IORegistry key list.

/// A titled group of rows on a raised near-black surface.
struct InspectorSection<Content: View>: View {
    var title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(title: title, trailing: trailing)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Lagoon.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Lagoon.stroke, lineWidth: 1)
            )
        }
    }
}

/// A label/value row that hides itself when the value is unknown, with an
/// optional copy button.
struct InspectorRow: View {
    var label: String
    var value: String?
    var monospaced: Bool = false
    var copyable: Bool = false

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                KeyValueRow(label: label, value: value, monospaced: monospaced)
                if copyable {
                    WindowCopyButton(value: value, help: "Copy \(label)")
                }
            }
        }
    }
}

/// Icon, title and subtitle at the top of the inspector.
struct InspectorHeader<Icon: View, Accessory: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var icon: Icon
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Lagoon.machineFont)
                        .foregroundStyle(Lagoon.textPrimary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(Lagoon.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            accessory
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// Tappable row that selects a related item (a child device, the port).
struct InspectorLinkRow: View {
    var systemName: String
    var title: String
    var detail: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Lagoon.accent)
                    .frame(width: 16)
                Text(title)
                    .foregroundStyle(Lagoon.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Lagoon.textTertiary)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Text field for a port's custom name. Commits on Return or when focus
/// leaves; an empty name restores the catalogue or generic name.
struct PortNameEditor: View {
    var store: PortStore
    var port: PhysicalPort

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $draft)
                .focused($isFocused)
                .onSubmit(commit)
                .accessibilityLabel("Name for \(port.label.title)")
            Button {
                draft = ""
                store.renamePort(port.key, to: nil)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(port.label.source != .user)
            .help("Use the default name")
            .accessibilityLabel("Reset name")
        }
        .onAppear { draft = currentName }
        .onChange(of: port.key) { draft = currentName }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    /// The user's name, or empty when the port uses its default name.
    private var currentName: String {
        port.label.source == .user ? (port.label.location ?? "") : ""
    }

    /// The default name the port falls back to.
    private var placeholder: String {
        port.label.source == .user ? "\(port.label.connector) \(port.label.number)" : port.label.title
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != currentName else { return }
        store.renamePort(port.key, to: trimmed.isEmpty ? nil : trimmed)
    }
}

/// Raw IORegistry properties, or a hint pointing at the setting that shows them.
struct InspectorRawKeysSection: View {
    var properties: PropertyBag?
    var showRawKeys: Bool

    @State private var isExpanded = false

    var body: some View {
        let count = properties?.values.count ?? 0
        InspectorSection(title: "IORegistry keys", trailing: showRawKeys && count > 0 ? "\(count)" : nil) {
            if !showRawKeys {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw registry values are hidden. Turn on “Show raw IORegistry keys” in Settings › Advanced to see them here.")
                        .font(.callout)
                        .foregroundStyle(Lagoon.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Advanced Settings…") {
                        WindowManager.shared.showSettings(tab: .advanced)
                    }
                    .buttonStyle(.link)
                }
            } else if let properties, !properties.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    rawList(properties)
                        .padding(.top, 6)
                } label: {
                    HStack {
                        Text(isExpanded ? "Hide keys" : "Show \(count) keys")
                            .foregroundStyle(Lagoon.textPrimary)
                        Spacer()
                        WindowCopyButton(value: copyText(properties), help: "Copy all keys")
                    }
                }
            } else {
                Text("No raw keys were captured for this item.")
                    .font(.callout)
                    .foregroundStyle(Lagoon.textSecondary)
            }
        }
    }

    private func rawList(_ properties: PropertyBag) -> some View {
        LazyVStack(alignment: .leading, spacing: 7) {
            ForEach(properties.keys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 1) {
                    Text(key)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Lagoon.accent.opacity(0.85))
                    Text(properties[key]?.displayString ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Lagoon.textPrimary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func copyText(_ properties: PropertyBag) -> String {
        properties.keys
            .map { "\($0) = \(properties[$0]?.displayString ?? "")" }
            .joined(separator: "\n")
    }
}

/// The charger's power profiles (PDOs) with the active one highlighted.
struct PowerProfilesGrid: View {
    var profiles: [PowerProfile]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("#")
                Text("Voltage")
                Text("Current")
                Text("Power")
                Text("")
            }
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(Lagoon.textTertiary)

            ForEach(profiles) { profile in
                GridRow {
                    Text("\(profile.index)")
                        .foregroundStyle(Lagoon.textTertiary)
                    Text(Format.voltage(millivolts: profile.millivolts))
                    Text(Format.current(milliamps: profile.maxMilliamps))
                    Text(Format.power(milliwatts: profile.maxMilliwatts))
                    if profile.isActive {
                        Text("Active")
                            .font(Lagoon.chipFont)
                            .foregroundStyle(Lagoon.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Lagoon.accent))
                    } else {
                        Text("")
                    }
                }
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(profile.isActive ? Lagoon.accent : Lagoon.textPrimary)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Inspector-only formatting.
enum InspectorFormat {
    static func registryID(_ id: UInt64) -> String { String(format: "0x%llx", id) }

    static func usbClass(_ value: Int) -> String {
        let name: String
        switch value {
        case 0x00: name = "Defined per interface"
        case 0x02: name = "Communications"
        case 0x09: name = "Hub"
        case 0x11: name = "Billboard"
        case 0xDC: name = "Diagnostic"
        case 0xE0: name = "Wireless controller"
        case 0xEF: name = "Miscellaneous"
        case 0xFF: name = "Vendor specific"
        default: name = "Class"
        }
        return "\(name) (\(String(format: "0x%02x", value)))"
    }

    static func pdRevision(_ revision: Int) -> String {
        switch revision {
        case 1: return "USB-PD 2.0"
        case 2: return "USB-PD 3.0"
        case 3: return "USB-PD 3.1"
        default: return "Revision \(revision)"
        }
    }

    static func lanes(_ link: LinkInfo) -> String? {
        guard let lanes = link.lanes else { return nil }
        return link.isAsymmetric ? "\(lanes) (asymmetric)" : "\(lanes)"
    }

    static func capturedAt(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}
