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

    var fileExtension: String {
        switch self {
        case .json, .raw: return "json"
        case .markdown: return "md"
        }
    }

    var contentType: UTType {
        switch self {
        case .json, .raw: return .json
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

/// Save panels for exports (docs/SPEC.md §2.2 and §6).
///
/// The panel carries a "Redact serial numbers" checkbox bound to the
/// `redactExports` setting; the data is generated after the panel closes so
/// the choice applies to this export.
enum ExportController {
    static func export(_ kind: ExportKind, store: PortStore) {
        NSApp.activate()

        if kind == .raw && store.raw == nil {
            showAlert(message: "No raw capture yet",
                      information: "Bus Stop has not finished reading the ports. Try again in a moment.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export \(kind.title.replacingOccurrences(of: "…", with: ""))"
        panel.nameFieldStringValue = defaultFileName(for: kind, model: store.snapshot.machine.model, date: Date())
        panel.allowedContentTypes = [kind.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let redact = NSButton(checkboxWithTitle: "Redact serial numbers", target: nil, action: nil)
        redact.state = store.settings.redactExports ? .on : .off
        panel.accessoryView = accessoryView(containing: redact)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.settings.redactExports = redact.state == .on

        do {
            let data: Data
            switch kind {
            case .json:
                data = try store.exportJSON()
            case .markdown:
                data = Data(store.exportMarkdown().utf8)
            case .raw:
                guard let raw = try store.exportRawJSON() else {
                    showAlert(message: "No raw capture yet",
                              information: "Bus Stop has not finished reading the ports. Try again in a moment.")
                    return
                }
                data = raw
            }
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert(message: "Could not export", information: error.localizedDescription)
        }
    }

    /// "Bus Stop Mac16,5 2026-10-04 1630.json",
    /// "Bus Stop raw capture Mac16,5 2026-10-04 1630.json".
    static func defaultFileName(for kind: ExportKind, model: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = formatter.string(from: date)
        // Slashes and colons are not allowed in file names.
        let safeModel = model.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        switch kind {
        case .json, .markdown:
            return "Bus Stop \(safeModel) \(stamp).\(kind.fileExtension)"
        case .raw:
            return "Bus Stop raw capture \(safeModel) \(stamp).\(kind.fileExtension)"
        }
    }

    private static func accessoryView(containing checkbox: NSButton) -> NSView {
        let stack = NSStackView(views: [checkbox])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return stack
    }

    private static func showAlert(message: String, information: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = information
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
