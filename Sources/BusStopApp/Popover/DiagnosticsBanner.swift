import BusStopCore
import SwiftUI

/// Banner shown when at least one warning or critical diagnostic exists
/// (docs/SPEC.md §3.2, item 3). Shows the most serious finding, expands to
/// list them all, and opens the topology window when clicked.
struct DiagnosticsBanner: View {
    /// Warnings and critical findings, most severe first.
    var diagnostics: [Diagnostic]

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The findings worth a banner, most severe first.
    static func relevant(_ diagnostics: [Diagnostic]) -> [Diagnostic] {
        diagnostics
            .filter { $0.severity >= .warning }
            .sorted { $0.severity > $1.severity }
    }

    var body: some View {
        if let first = diagnostics.first {
            let color = Lagoon.severityColor(first.severity)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        openInTopology(first)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: Lagoon.severitySymbol(first.severity))
                                .lagoonFont(size: 15, weight: .semibold)
                                .foregroundStyle(color)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(first.title)
                                    .lagoonFont(.callout, weight: .semibold)
                                    .foregroundStyle(Lagoon.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if diagnostics.count > 1 {
                                    Text(PopoverText.count(diagnostics.count - 1, "more issue", "more issues"))
                                        .lagoonFont(.caption)
                                        .foregroundStyle(Lagoon.textSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show in the topology window")
                    .accessibilityLabel("\(first.severity == .critical ? "Critical" : "Warning"): \(first.title)")
                    .accessibilityHint("Opens the topology window")

                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .lagoonFont(size: 11, weight: .bold)
                            .foregroundStyle(Lagoon.textSecondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide details" : "Show all issues")
                    .accessibilityLabel(isExpanded ? "Hide details" : "Show all issues")
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(diagnostics) { diagnostic in
                            DiagnosticRow(diagnostic: diagnostic) {
                                openInTopology(diagnostic)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
                    .fill(Lagoon.surface)
            )
            .background(
                RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
                    .fill(color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }

    private func openInTopology(_ diagnostic: Diagnostic) {
        if let deviceID = diagnostic.deviceID {
            WindowManager.shared.showTopology(selecting: .device(deviceID))
        } else if let portKey = diagnostic.portKey {
            WindowManager.shared.showTopology(selecting: .port(portKey))
        } else {
            WindowManager.shared.showTopology()
        }
    }
}

/// One finding in the expanded banner.
private struct DiagnosticRow: View {
    var diagnostic: Diagnostic
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Lagoon.severitySymbol(diagnostic.severity))
                    .lagoonFont(.caption)
                    .foregroundStyle(Lagoon.severityColor(diagnostic.severity))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(diagnostic.title)
                        .lagoonFont(.caption, weight: .semibold)
                        .foregroundStyle(Lagoon.textPrimary)
                    Text(diagnostic.detail)
                        .lagoonFont(.caption)
                        .foregroundStyle(Lagoon.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let suggestion = diagnostic.suggestion {
                        Text(suggestion)
                            .lagoonFont(.caption)
                            .foregroundStyle(Lagoon.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the topology window")
    }
}
