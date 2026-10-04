import BusStopCore
import Foundation

/// The version reported by `busstop --version`.
///
/// Inside the app bundle (`Bus Stop.app/Contents/Helpers/busstop`, or a
/// symbolic link to it made by `scripts/install.sh --link-cli`) the bundle's
/// `Info.plist` is the authority, because release builds stamp the version
/// from the git tag. A bare `swift build` binary reports `BusStopVersion.string`.
enum VersionInfo {
    /// "1.0.0" or "1.0.0 (build 42)".
    static var line: String {
        let info = bundleInfo()
        return BusStopVersion.display(version: info?.version, build: info?.build)
    }

    /// `CFBundleShortVersionString` and `CFBundleVersion` of the app bundle
    /// that contains this executable, or nil when it does not run from one.
    static func bundleInfo() -> (version: String?, build: String?)? {
        let invoked = Bundle.main.executableURL
            ?? CommandLine.arguments.first.map { URL(fileURLWithPath: $0) }
        guard let executable = invoked?.resolvingSymlinksInPath() else { return nil }
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        guard contents.lastPathComponent == "Contents" else { return nil }
        let plistURL = contents.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return (dictionary["CFBundleShortVersionString"] as? String, dictionary["CFBundleVersion"] as? String)
    }
}
