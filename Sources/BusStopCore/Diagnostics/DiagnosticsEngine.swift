import Foundation

/// Evaluates the diagnostic rules in SPEC §5.4 "Diagnostics".
public enum DiagnosticsEngine {
    /// - Parameters:
    ///   - snapshot: the freshly built snapshot (its `diagnostics` are ignored).
    ///   - raw: the raw capture it came from (for keys the model does not carry).
    ///   - baseline: overcurrent counts per port key at app launch, to detect increases.
    public static func evaluate(_ snapshot: HostSnapshot, raw: RawSnapshot?, baseline: [String: Int] = [:]) -> [Diagnostic] {
        []
    }
}
