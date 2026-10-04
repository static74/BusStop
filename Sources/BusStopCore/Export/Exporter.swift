import Foundation

/// Export formats offered by the app and the CLI.
public enum Exporter {
    /// Pretty-printed, key-sorted JSON of the snapshot. When `redact` is true,
    /// serial numbers and the computer name are replaced by "REDACTED".
    public static func json(_ snapshot: HostSnapshot, redact: Bool = true) throws -> Data {
        fatalError("not implemented")
    }

    /// A Markdown report: machine, power summary, one section per port with a
    /// device tree, displays, diagnostics.
    public static func markdown(_ snapshot: HostSnapshot, redact: Bool = true) -> String {
        fatalError("not implemented")
    }

    /// Pretty-printed, key-sorted JSON of a raw capture (for bug reports and
    /// test fixtures). Serials are redacted when `redact` is true.
    public static func rawJSON(_ raw: RawSnapshot, redact: Bool = true) throws -> Data {
        fatalError("not implemented")
    }

    /// Decodes a raw capture produced by `rawJSON`.
    public static func decodeRaw(_ data: Data) throws -> RawSnapshot {
        fatalError("not implemented")
    }

    /// Plain-text tree used by the CLI's default output.
    public static func textTree(_ snapshot: HostSnapshot) -> String {
        fatalError("not implemented")
    }
}
