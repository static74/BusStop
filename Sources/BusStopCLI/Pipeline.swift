import BusStopCore
import Foundation

/// Turns captures into snapshots and documents, the same way the app does.
enum Pipeline {
    /// Builds the topology and evaluates diagnostics.
    ///
    /// Raw IORegistry properties are left off ports and devices: they only
    /// matter to the app's inspector, and `--raw` prints all of them anyway.
    ///
    /// - Parameter baseline: overcurrent counts per port at the start of a
    ///   `--watch` session, so increases raise a diagnostic.
    static func snapshot(from raw: RawSnapshot, isDemo: Bool, baseline: [String: Int] = [:]) -> HostSnapshot {
        let options = BuildOptions(includeRawProperties: false, isDemo: isDemo)
        var snapshot = TopologyBuilder.build(raw, options: options)
        snapshot.diagnostics = DiagnosticsEngine.evaluate(snapshot, raw: raw, baseline: baseline)
        return snapshot
    }

    /// Overcurrent counts per port key, recorded from the first snapshot of a
    /// session.
    static func overcurrentBaseline(of snapshot: HostSnapshot) -> [String: Int] {
        var baseline: [String: Int] = [:]
        for port in snapshot.ports {
            if let count = port.statistics?.overcurrentCount { baseline[port.id] = count }
        }
        return baseline
    }

    /// Reads the capture for a one-shot run.
    static func capture(for options: CLIOptions) throws -> RawSnapshot {
        switch options.source {
        case .live:
            return LiveSource.capture(includeSMC: options.includeSMC)
        case .demo(let scenario):
            return scenario.raw(at: Date())
        case .file(let path):
            return try loadCapture(path)
        }
    }

    /// Reads and decodes a raw capture file, or standard input for `"-"`.
    static func loadCapture(_ path: String) throws -> RawSnapshot {
        let data: Data
        let displayName = path == "-" ? "standard input" : path
        if path == "-" {
            do {
                data = try FileHandle.standardInput.readToEnd() ?? Data()
            } catch {
                throw CLIFailure.runtime("cannot read standard input: \(error.localizedDescription)")
            }
        } else {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw CLIFailure.runtime("cannot read \(path): no such file")
            }
            guard !isDirectory.boolValue else {
                throw CLIFailure.runtime("cannot read \(path): it is a directory")
            }
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw CLIFailure.runtime("cannot read \(path): \(error.localizedDescription)")
            }
        }
        guard !data.isEmpty else {
            throw CLIFailure.runtime("\(displayName) is empty; expected a capture saved with 'busstop --raw'")
        }
        do {
            return try Exporter.decodeRaw(data)
        } catch {
            throw CLIFailure.runtime(
                "\(displayName) is not a Bus Stop raw capture (\(describe(error))). Save one with 'busstop --raw'.")
        }
    }

    /// The document printed by a one-shot run, ending with a newline.
    static func render(_ raw: RawSnapshot, options: CLIOptions) throws -> String {
        let isDemo: Bool
        if case .demo = options.source { isDemo = true } else { isDemo = false }

        switch options.format {
        case .raw:
            return try jsonText(Exporter.rawJSON(raw, redact: options.redact), what: "raw capture")
        case .json:
            let snapshot = snapshot(from: raw, isDemo: isDemo)
            return try jsonText(Exporter.json(snapshot, redact: options.redact), what: "snapshot")
        case .markdown:
            let snapshot = snapshot(from: raw, isDemo: isDemo)
            return Exporter.markdown(snapshot, redact: options.redact)
        case .text:
            let snapshot = snapshot(from: raw, isDemo: isDemo)
            return Exporter.textTree(snapshot)
        }
    }

    /// UTF-8 text of encoded JSON. `encode` is an autoclosure so encoding
    /// errors are reported with a readable message.
    private static func jsonText(_ encode: @autoclosure () throws -> Data, what: String) throws -> String {
        let data: Data
        do {
            data = try encode()
        } catch {
            throw CLIFailure.runtime("cannot encode the \(what) as JSON: \(describe(error))")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIFailure.runtime("cannot encode the \(what) as UTF-8 text")
        }
        return text
    }

    /// A one-line description of a decoding or encoding error, with the
    /// coding path where it happened ("missing key 'machine'").
    static func describe(_ error: Error) -> String {
        func location(_ path: [CodingKey]) -> String {
            guard !path.isEmpty else { return "" }
            let text = path.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
            return " at \(text.hasPrefix(".") ? String(text.dropFirst()) : text)"
        }
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, let context):
                return "missing key '\(key.stringValue)'\(location(context.codingPath))"
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                return context.debugDescription + location(context.codingPath)
            @unknown default:
                return String(describing: decoding)
            }
        }
        if let encoding = error as? EncodingError {
            switch encoding {
            case .invalidValue(_, let context):
                return context.debugDescription + location(context.codingPath)
            @unknown default:
                return String(describing: encoding)
            }
        }
        return error.localizedDescription
    }
}
