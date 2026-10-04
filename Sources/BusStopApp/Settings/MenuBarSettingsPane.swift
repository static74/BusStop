import BusStopCore
import SwiftUI

/// Menu Bar: icon style with live previews and what text sits next to it.
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
                LabeledContent("Example") {
                    MenuBarMockup(icon: settings.menuBarIcon, text: exampleText(settings.menuBarText))
                }
                SettingsCaption("Numbers use monospaced digits so the menu bar does not shift as they change.")
            }
        }
        .settingsPaneStyle()
    }

    /// Example text using live numbers when available.
    private func exampleText(_ mode: MenuBarTextMode) -> String {
        let snapshot = store.snapshot
        let devices = store.hasLoaded ? snapshot.deviceCount : 5
        let milliwatts = (store.hasLoaded ? snapshot.power.headlineMilliwatts : nil) ?? 38_000
        let power = Format.power(milliwatts: milliwatts)
        switch mode {
        case .none: return ""
        case .power: return power
        case .devices: return "\(devices)"
        case .both: return "\(devices) · \(power)"
        }
    }
}

/// The icon for a menu bar style at menu bar size.
struct MenuBarIconPreview: View {
    var style: MenuBarIconStyle
    var size: CGFloat = 16

    var body: some View {
        if let symbol = style.symbolName {
            Image(systemName: symbol)
                .font(.system(size: size * 0.85, weight: .medium))
                .frame(width: size, height: size)
        } else {
            SettingsBusStopSign(size: size)
        }
    }
}

/// The default menu bar icon drawn with shapes: a roundel sign on a pole.
struct SettingsBusStopSign: View {
    var size: CGFloat = 16

    var body: some View {
        let ring = size * 0.62
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .strokeBorder(lineWidth: max(1.2, size * 0.12))
                Capsule()
                    .frame(width: ring * 1.12, height: max(1.6, size * 0.17))
            }
            .frame(width: ring, height: ring)
            Rectangle()
                .frame(width: max(1.2, size * 0.11), height: size * 0.3)
            Capsule()
                .frame(width: size * 0.38, height: max(1, size * 0.07))
        }
        .frame(width: size, height: size)
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
                MenuBarIconPreview(style: style, size: 18)
                    .foregroundStyle(Lagoon.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                Text(style.title)
                    .font(.caption)
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
struct MenuBarMockup: View {
    var icon: MenuBarIconStyle
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .foregroundStyle(Lagoon.textTertiary)
            HStack(spacing: 5) {
                MenuBarIconPreview(style: icon, size: 15)
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Lagoon.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.14)))
            Text("Sun 9:41")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Lagoon.textTertiary)
        }
        .font(.system(size: 12))
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
