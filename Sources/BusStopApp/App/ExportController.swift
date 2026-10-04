import AppKit
import BusStopCore
import UniformTypeIdentifiers

enum ExportKind: String, CaseIterable, Identifiable {
    /// Interpreted snapshot as JSON.
    case json
    /// Human-readable Markdown report.
    case markdown
    /// Raw IORegistry capture as JSON (for bug reports).
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: return "Snapshot (JSON)…"
        case .markdown: return "Report (Markdown)…"
        case .raw: return "Raw Capture for Bug Reports…"
        }
    }
}

/// Save panels for exports. Placeholder; implemented by the app shell.
enum ExportController {
    static func export(_ kind: ExportKind, store: PortStore) {}
}
