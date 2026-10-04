import Foundation

/// The version of this source tree.
///
/// `scripts/build-app.sh` reads `string` as the default
/// `CFBundleShortVersionString`, and release builds override it from the git
/// tag. Bump `string` and add a `CHANGELOG.md` entry together.
public enum BusStopVersion {
    /// Marketing version, e.g. "1.0.0".
    public static let string = "1.0.0"

    /// The project's home page.
    public static let projectURL = "https://github.com/static74/BusStop"

    /// A version line such as "1.0.0" or "1.0.1 (build 42)".
    ///
    /// - Parameters:
    ///   - version: the bundle's `CFBundleShortVersionString`, when the binary
    ///     runs from an app bundle. Falls back to `string` when nil or empty.
    ///   - build: the bundle's `CFBundleVersion`. Left out when nil or empty.
    public static func display(version: String? = nil, build: String? = nil) -> String {
        let trimmedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var line = trimmedVersion.isEmpty ? string : trimmedVersion
        let trimmedBuild = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedBuild.isEmpty { line += " (build \(trimmedBuild))" }
        return line
    }
}
