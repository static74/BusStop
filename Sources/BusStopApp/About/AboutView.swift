import AppKit
import SwiftUI

/// Root view of the About window: icon, name, version, what Bus Stop
/// promises, credits and a link to the project. Text follows the Text Size
/// setting; the window grows taller to fit it.
struct AboutView: View {
    /// The project page. A literal, so it always parses.
    private static let repositoryURL = URL(string: "https://github.com/static74/BusStop")!

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .shadow(color: Lagoon.accent.opacity(0.35), radius: 16)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("Bus Stop")
                    .lagoonFont(size: 24, weight: .bold, design: .rounded)
                    .foregroundStyle(Lagoon.textPrimary)
                Text(Self.versionText)
                    .lagoonFont(.callout, monospacedDigits: true)
                    .foregroundStyle(Lagoon.textSecondary)
                    .textSelection(.enabled)
            }

            Text("A live map of every port on your Mac.")
                .lagoonFont(.headline, weight: .semibold, design: .rounded)
                .multilineTextAlignment(.center)
                .foregroundStyle(Lagoon.accent)

            VStack(spacing: 3) {
                Text("Free and open source under the MIT License.")
                Text("No network access. No telemetry. Everything stays on your Mac.")
            }
            .lagoonFont(.callout)
            .foregroundStyle(Lagoon.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Lagoon.stroke)
                .frame(width: 120, height: 1)
                .padding(.vertical, 2)

            Text("Port locations from PortScope by Alex Zenla. IOKit research informed by WhatPort and WhatCable by Darryl Morley.")
                .lagoonFont(.caption)
                .foregroundStyle(Lagoon.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.open(Self.repositoryURL)
            } label: {
                Label("View on GitHub", systemImage: "arrow.up.right.square")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glass(.regular.tint(Lagoon.accent.opacity(0.25))))
            .padding(.top, 2)
            .help(Self.repositoryURL.absoluteString)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: 380)
        .frame(minHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background { background }
        .preferredColorScheme(.dark)
        .tint(Lagoon.accent)
        .lagoonFont(.body)
        .lagoonTextScale(AppSettings.shared.textSize)
    }

    private var background: some View {
        ZStack {
            Lagoon.background
            RadialGradient(
                colors: [Lagoon.accent.opacity(0.16), Lagoon.accent.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 0,
                endRadius: 220
            )
        }
        .ignoresSafeArea()
    }

    /// "Version 1.2 (34)" from the bundle, or "development build" when run
    /// outside an app bundle.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else {
            return "development build"
        }
        if let build = info?["CFBundleVersion"] as? String, !build.isEmpty, build != version {
            return "Version \(version) (\(build))"
        }
        return "Version \(version)"
    }
}
