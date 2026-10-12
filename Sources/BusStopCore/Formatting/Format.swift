import Foundation

/// Unit formatting shared by the app, the CLI and exports.
///
/// Deliberately locale-independent (decimal point, SI units) so CLI output and
/// tests are stable. The app may wrap these for localisation later.
public enum Format {
    /// "480 Mb/s", "5 Gb/s", "10 Gb/s", "40 Gb/s", "1.5 Mb/s", "12 Mb/s".
    public static func dataRate(bitsPerSecond bps: Int64) -> String {
        if bps >= 1_000_000_000 {
            return trimmed(Double(bps) / 1_000_000_000) + " Gb/s"
        }
        if bps >= 1_000_000 {
            return trimmed(Double(bps) / 1_000_000) + " Mb/s"
        }
        if bps >= 1_000 {
            return trimmed(Double(bps) / 1_000) + " kb/s"
        }
        return "\(bps) b/s"
    }

    /// "4.5 W", "96 W", "0.5 W", "120 mW" (below 0.1 W).
    /// Whole watts drop the decimal at 10 W and above.
    public static func power(milliwatts mw: Int) -> String {
        if mw == 0 { return "0 W" }
        if abs(mw) < 100 { return "\(mw) mW" }
        let watts = Double(mw) / 1000
        if abs(watts) >= 10 { return "\(Int(watts.rounded())) W" }
        return oneDecimal(watts) + " W"
    }

    /// Compact form for the menu bar: "38W", "4.5W".
    /// `decimals` forces 0 or 1 decimal places; nil uses `power(milliwatts:)` rules.
    public static func compactPower(milliwatts mw: Int, decimals: Int? = nil) -> String {
        guard let decimals else {
            return power(milliwatts: mw).replacingOccurrences(of: " ", with: "")
        }
        let watts = Double(mw) / 1000
        if decimals <= 0 { return "\(Int(watts.rounded()))W" }
        return String(format: "%.1fW", watts)
    }

    /// Removes control characters (including ANSI escape sequences) and
    /// collapses runs of whitespace, so device-supplied names cannot alter a
    /// terminal or break one-line output.
    public static func terminalSafe(_ text: String) -> String {
        var result = ""
        result.unicodeScalars.reserveCapacity(text.unicodeScalars.count)
        var lastWasSpace = false
        for scalar in text.unicodeScalars {
            let isControl = scalar.properties.generalCategory == .control
                || scalar.properties.generalCategory == .format
                || (0x80...0x9F).contains(scalar.value)
            if isControl || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace && !result.isEmpty { result.unicodeScalars.append(" ") }
                lastWasSpace = true
            } else {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// "20 V", "5 V", "15 V", "9.5 V".
    public static func voltage(millivolts mv: Int) -> String {
        trimmed(Double(mv) / 1000, maxFractionDigits: 1) + " V"
    }

    /// "3 A", "4.7 A", "1.49 A", "500 mA" (below 1 A).
    public static func current(milliamps ma: Int) -> String {
        if abs(ma) < 1000 { return "\(ma) mA" }
        return trimmed(Double(ma) / 1000, maxFractionDigits: 2) + " A"
    }

    /// "20 V × 4.7 A"
    public static func contract(millivolts mv: Int, milliamps ma: Int) -> String {
        "\(voltage(millivolts: mv)) × \(current(milliamps: ma))"
    }

    /// `0x05ac`
    public static func hex4(_ value: Int) -> String {
        String(format: "0x%04x", value)
    }

    /// `0x01100000`
    public static func hex8(_ value: UInt32) -> String {
        String(format: "0x%08x", value)
    }

    /// BCD USB version (`bcdUSB` 0x0320 → "3.2", 0x0210 → "2.1", 0x0200 → "2.0", 0x0201 → "2.01").
    public static func bcdVersion(_ bcd: Int) -> String {
        let major = (bcd >> 8) & 0xFF
        let minor = (bcd >> 4) & 0xF
        let sub = bcd & 0xF
        let majorString = String(major, radix: 16)
        if sub == 0 { return "\(majorString).\(minor)" }
        return "\(majorString).\(minor)\(sub)"
    }

    /// "just now", "12 s ago", "3 min ago", "2 h ago".
    public static func relative(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds) s ago" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3600) h ago" }
        return "\(seconds / 86_400) d ago"
    }

    // MARK: Helpers

    /// Up to `maxFractionDigits` decimals, trailing zeros removed: 10 → "10", 1.5 → "1.5", 0.48 → "0.48".
    static func trimmed(_ value: Double, maxFractionDigits: Int = 2) -> String {
        var s = String(format: "%.\(maxFractionDigits)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    static func oneDecimal(_ value: Double) -> String {
        trimmed(value, maxFractionDigits: 1)
    }
}
