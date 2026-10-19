import AppKit
import BusStopCore
import SwiftUI

/// Menu Bar: icon style with live previews, what text sits next to it, how
/// precisely power is shown and which port is pinned next to the icon.
struct MenuBarSettingsPane: View {
    var store: PortStore

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Icon") {
                HStack(spacing: 10) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        MenuBarIconTile(style: style, isSelected: settings.menuBarIcon == style) {
                            store.settings.menuBarIcon = style
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Text next to the icon") {
                Picker("Show", selection: $settings.menuBarText) {
                    ForEach(MenuBarTextMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Picker("Power precision", selection: $settings.menuBarPowerPrecision) {
                    ForEach(PowerPrecision.allCases) { precision in
                        Text(precision.title).tag(precision)
                    }
                }
                .disabled(!showsPower(settings))
                LabeledContent("Example") {
                    MenuBarMockup(icon: settings.menuBarIcon, text: exampleText(settings))
                }
                SettingsCaption("Automatic shows one decimal below 10 W (4.5W) and whole watts above (38W). Numbers use monospaced digits so the menu bar does not shift as they change.")
            }

            Section("Pinned port") {
                Picker("Port", selection: pinnedPort) {
                    Text("None").tag(PortKey?.none)
                    ForEach(store.snapshot.ports) { port in
                        Text(port.label.title).tag(PortKey?.some(port.key))
                    }
                }
                Picker("Show", selection: $settings.menuBarPinnedValue) {
                    ForEach(PinnedPortValue.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .disabled(pinnedPort.wrappedValue == nil)
                SettingsCaption("Shows the port's speed (40G) or power (\u{2193}61W in, \u{2191}4.5W out) after the text above; its name is in the tooltip. \u{2264} marks a USB power budget or charger contract, not a measurement. Speed updates as soon as the hardware changes. Measured watts refresh about every 10 seconds while the popover is closed; figures marked \u{2264} refresh when the hardware changes, or within a minute. A port card's context menu in the popover pins it too.")
            }
        }
        .settingsPaneStyle()
    }

    /// The pinned port, or nil when none is pinned or the pinned port is not
    /// on this Mac. Such a pin shows as None but stays stored.
    private var pinnedPort: Binding<PortKey?> {
        Binding(
            get: { store.pinnedPortKey.flatMap { store.snapshot.port($0) != nil ? $0 : nil } },
            set: { store.pinPort($0) }
        )
    }

    private func showsPower(_ settings: AppSettings) -> Bool {
        settings.menuBarText == .power || settings.menuBarText == .both
            || (pinnedPort.wrappedValue != nil && settings.menuBarPinnedValue != .speed)
    }

    /// The text the menu bar item shows, from the same builder: live numbers
    /// once the first capture is in, otherwise 5 devices and 38 W.
    private func exampleText(_ settings: AppSettings) -> String {
        guard store.hasLoaded else {
            return StatusItemController.menuBarText(mode: settings.menuBarText, deviceCount: 5, milliwatts: 38_000,
                                                    precision: settings.menuBarPowerPrecision)
        }
        return StatusItemController.menuBarTitle(snapshot: store.snapshot, settings: settings,
                                                 pinnedKey: store.pinnedPortKey)
    }
}

/// The menu bar item's own template image for a style, at its real size.
struct MenuBarIconPreview: View {
    var style: MenuBarIconStyle

    var body: some View {
        Image(nsImage: StatusIcon.image(for: style))
            .renderingMode(.template)
            .accessibilityHidden(true)
    }
}

/// A selectable tile showing one icon style in a mock menu bar.
struct MenuBarIconTile: View {
    var style: MenuBarIconStyle
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                MenuBarIconPreview(style: style)
                    .foregroundStyle(Lagoon.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Lagoon.well)
                    )
                Text(style.title)
                    .lagoonFont(.caption)
                    .foregroundStyle(isSelected ? Lagoon.accent : Lagoon.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Lagoon.accent.opacity(0.10) : Lagoon.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Lagoon.accent : Lagoon.stroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// A strip of menu bar with the Bus Stop item highlighted.
///
/// It copies the real menu bar, so it uses the menu bar's font size rather
/// than the Text Size setting, which the menu bar does not follow either.
struct MenuBarMockup: View {
    var icon: MenuBarIconStyle
    var text: String

    /// The size `StatusItemController` uses for the item's title.
    private static let menuBarFontSize = NSFont.menuBarFont(ofSize: 0).pointSize

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .foregroundStyle(Lagoon.textTertiary)
            HStack(spacing: 4) {
                MenuBarIconPreview(style: icon)
                if !text.isEmpty {
                    Text(text)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Lagoon.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Lagoon.menuBarItemHighlight))
            Text("Sun 9:41")
                .foregroundStyle(Lagoon.textTertiary)
        }
        .font(.system(size: Self.menuBarFontSize))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: Lagoon.menuBarBackdrop,
                                     startPoint: .leading, endPoint: .trailing))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? "Icon only" : "Menu bar shows \(text)")
    }
}
