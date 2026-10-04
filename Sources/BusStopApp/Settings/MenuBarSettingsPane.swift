import AppKit
import BusStopCore
import SwiftUI

/// Menu Bar: icon style with live previews, what text sits next to it and
/// how precisely power is shown.
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
                .disabled(!showsPower(settings.menuBarText))
                LabeledContent("Example") {
                    MenuBarMockup(icon: settings.menuBarIcon, text: exampleText(settings))
                }
                SettingsCaption("Automatic shows one decimal below 10 W (4.5W) and whole watts above (38W). Numbers use monospaced digits so the menu bar does not shift as they change.")
            }
        }
        .settingsPaneStyle()
    }

    private func showsPower(_ mode: MenuBarTextMode) -> Bool {
        mode == .power || mode == .both
    }

    /// The text the menu bar item shows, formatted the same way: live numbers
    /// once the first capture is in, otherwise 5 devices and 38 W.
    private func exampleText(_ settings: AppSettings) -> String {
        let snapshot = store.snapshot
        let devices = store.hasLoaded ? snapshot.deviceCount : 5
        let milliwatts = store.hasLoaded ? snapshot.power.headlineMilliwatts : 38_000
        let power = milliwatts.map {
            Format.compactPower(milliwatts: $0, decimals: settings.menuBarPowerPrecision.decimals)
        }
        switch settings.menuBarText {
        case .none: return ""
        case .power: return power ?? ""
        case .devices: return "\(devices)"
        case .both: return power.map { "\(devices) \u{00B7} \($0)" } ?? "\(devices)"
        }
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
                            .fill(Color.white.opacity(0.06))
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
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.14)))
            Text("Sun 9:41")
                .foregroundStyle(Lagoon.textTertiary)
        }
        .font(.system(size: Self.menuBarFontSize))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1B2A3A), Color(hex: 0x0E1A1C)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? "Icon only" : "Menu bar shows \(text)")
    }
}
