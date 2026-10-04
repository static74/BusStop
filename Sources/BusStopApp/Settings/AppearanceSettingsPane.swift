import BusStopCore
import SwiftUI

/// Appearance: background opacity, glass tint, text size and link animation.
struct AppearanceSettingsPane: View {
    var store: PortStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Background") {
                AppearancePreviewSwatch(opacity: settings.backgroundOpacity, tint: settings.glassTint)
                Slider(value: $settings.backgroundOpacity, in: 0.6...1, step: 0.01) {
                    Text("Opacity")
                } minimumValueLabel: {
                    Text(verbatim: "60%").monospacedDigit()
                } maximumValueLabel: {
                    Text(verbatim: "100%").monospacedDigit()
                }
                LabeledContent("Current", value: percent(settings.backgroundOpacity))
                SettingsCaption(reduceTransparency
                    ? "Reduce Transparency is on in System Settings, so backgrounds are always solid."
                    : "Lower values let a hint of the desktop show through. 100% is fully solid and easiest to read.")
            }

            Section("Glass controls") {
                Slider(value: $settings.glassTint, in: 0...0.5, step: 0.01) {
                    Text("Turquoise tint")
                } minimumValueLabel: {
                    Text(verbatim: "0%").monospacedDigit()
                } maximumValueLabel: {
                    Text(verbatim: "50%").monospacedDigit()
                }
                LabeledContent("Preview") {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            GlassIconButton(systemName: "arrow.clockwise", help: "Refresh", tint: settings.glassTint) {}
                            GlassIconButton(systemName: "point.3.connected.trianglepath.dotted", help: "Open Topology",
                                            tint: settings.glassTint) {}
                            GlassIconButton(systemName: "gearshape", help: "Settings", tint: settings.glassTint) {}
                        }
                    }
                }
            }

            Section("Text") {
                Picker("Text size", selection: $settings.textSize) {
                    ForEach(TextSizeSetting.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Motion") {
                Toggle("Animate links in the topology graph", isOn: $settings.animateLinks)
                SettingsCaption(reduceMotion
                    ? "Reduce Motion is on in System Settings, so links stay still."
                    : "Small pulses travel along active links, faster for faster connections.")
            }
        }
        .settingsPaneStyle()
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

/// A miniature of a Bus Stop card over a busy "desktop", at the chosen
/// background opacity.
struct AppearancePreviewSwatch: View {
    var opacity: Double
    var tint: Double

    var body: some View {
        ZStack {
            wallpaper
            LagoonBackground(opacity: opacity)
            HStack(spacing: 10) {
                StatusRing(isActive: true, size: 11)
                PortIcon(kind: .usbC, isActive: true, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Left Front · USB-C")
                        .font(.system(.callout).weight(.semibold))
                        .foregroundStyle(Lagoon.textPrimary)
                    Text("Samsung T9 · 4.5 W")
                        .font(.caption)
                        .foregroundStyle(Lagoon.textSecondary)
                }
                Spacer(minLength: 8)
                SpeedChip(link: LinkInfo(family: .usb, generation: "USB 3.2 Gen 2", bitsPerSecond: 10_000_000_000))
            }
            .lagoonCard(padding: 10)
            .padding(.horizontal, 18)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Lagoon.stroke, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview at \(Int((opacity * 100).rounded())) percent opacity")
    }

    /// A colourful stand-in for the desktop behind the window.
    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3B5BDB), Color(hex: 0xC2255C), Color(hex: 0xF59F00)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color(hex: 0x12B886))
                .frame(width: 120, height: 120)
                .offset(x: -150, y: 20)
                .blur(radius: 18)
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 70, height: 70)
                .offset(x: 170, y: -30)
                .blur(radius: 14)
        }
    }
}
