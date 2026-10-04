import BusStopCore
import SwiftUI

/// The Diagnostics page: one card per finding, most severe first, with a
/// plain-English explanation and a suggested fix.
struct DiagnosticsDetailView: View {
    var store: PortStore
    var onShowPort: (PortKey) -> Void
    var onShowDevice: (String) -> Void

    var body: some View {
        let diagnostics = store.snapshot.diagnostics.sorted { lhs, rhs in
            lhs.severity == rhs.severity ? lhs.title < rhs.title : lhs.severity > rhs.severity
        }
        Group {
            if diagnostics.isEmpty {
                VStack(spacing: 0) {
                    WindowDetailHeader(title: "Diagnostics", subtitle: "Checks run on every refresh")
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    WindowEmptyState(
                        systemName: "checkmark.circle",
                        title: "No issues found",
                        message: "Every link runs as fast as both ends allow, chargers and hubs are within budget, and no port reports a problem."
                    )
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        WindowDetailHeader(title: "Diagnostics", subtitle: summary(diagnostics))
                        ForEach(diagnostics) { diagnostic in
                            DiagnosticCard(
                                diagnostic: diagnostic,
                                portTitle: diagnostic.portKey.flatMap { store.snapshot.port($0)?.label.title },
                                deviceName: diagnostic.deviceID.flatMap { store.snapshot.device(id: $0)?.name },
                                onShowPort: onShowPort,
                                onShowDevice: onShowDevice
                            )
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func summary(_ diagnostics: [Diagnostic]) -> String {
        var parts: [String] = []
        for severity in DiagnosticSeverity.allCases.reversed() {
            let count = diagnostics.filter { $0.severity == severity }.count
            guard count > 0 else { continue }
            switch severity {
            case .critical: parts.append(WindowText.count(count, "critical issue", "critical issues"))
            case .warning: parts.append(WindowText.count(count, "warning", "warnings"))
            case .info: parts.append(WindowText.count(count, "note", "notes"))
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// One finding: severity symbol, title, detail, suggestion and shortcuts.
struct DiagnosticCard: View {
    var diagnostic: Diagnostic
    var portTitle: String?
    var deviceName: String?
    var onShowPort: (PortKey) -> Void
    var onShowDevice: (String) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let color = Lagoon.severityColor(diagnostic.severity)
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Lagoon.severitySymbol(diagnostic.severity))
                .lagoonFont(size: 18, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.12)))
                .accessibilityLabel(severityName)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(diagnostic.title)
                        .lagoonFont(.headline, weight: .semibold)
                        .foregroundStyle(Lagoon.textPrimary)
                    Text(severityName.uppercased())
                        .lagoonFont(size: 9, weight: .heavy, design: .rounded)
                        .tracking(0.8)
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.14)))
                }
                Text(diagnostic.detail)
                    .lagoonFont(.callout)
                    .foregroundStyle(Lagoon.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if let suggestion = diagnostic.suggestion, !suggestion.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb")
                            .lagoonFont(size: 12, weight: .semibold)
                            .foregroundStyle(Lagoon.accent)
                        Text(suggestion)
                            .lagoonFont(.callout)
                            .foregroundStyle(Lagoon.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Lagoon.surfaceRaised))
                }

                if diagnostic.portKey != nil || diagnostic.deviceID != nil {
                    HStack(spacing: 10) {
                        if let key = diagnostic.portKey {
                            Button {
                                onShowPort(key)
                            } label: {
                                Label(portTitle.map { "Show \($0)" } ?? "Show Port", systemImage: "cable.connector")
                            }
                        }
                        if let id = diagnostic.deviceID, let deviceName {
                            Button {
                                onShowDevice(id)
                            } label: {
                                Label("Show \(deviceName)", systemImage: "info.circle")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
                .fill(Lagoon.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
                .strokeBorder(diagnostic.severity == .info ? WindowContrast.stroke(contrast) : color.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var severityName: String {
        switch diagnostic.severity {
        case .info: return "Note"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}
