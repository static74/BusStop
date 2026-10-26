import Foundation

/// The widget payload's file in the App Group container, shared by the app
/// (which writes it) and the widget extension (which reads it).
///
/// The group is `<team>.io.github.static74.busstop`. `scripts/build-app.sh`
/// writes the team into both Info.plists as `BusStopTeamID` when it signs with
/// a team's identity; an ad hoc build has no team, so no group and no file.
public struct WidgetPayloadFile: Sendable {
    public static let teamIDKey = "BusStopTeamID"
    public static let fileName = "widget-payload.json"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The App Group's identifier, or nil when `bundle` carries no team ID.
    public static func appGroupID(bundle: Bundle = .main) -> String? {
        guard let team = bundle.object(forInfoDictionaryKey: teamIDKey) as? String, !team.isEmpty else { return nil }
        return "\(team).io.github.static74.busstop"
    }

    /// The payload file in the App Group container, or nil without a team or a container.
    public static func appGroup(bundle: Bundle = .main) -> WidgetPayloadFile? {
        guard let group = appGroupID(bundle: bundle),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return WidgetPayloadFile(url: container.appending(path: fileName))
    }

    /// The payload, or nil when there is none yet, it does not decode or a newer Bus Stop wrote it.
    public func read() -> WidgetPayload? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(WidgetPayload.self, from: data),
              payload.schemaVersion <= WidgetPayload.currentSchemaVersion
        else { return nil }
        return payload
    }

    /// Atomic, so the extension never reads half a file; owner-only, since it names the user's devices.
    public func write(_ payload: WidgetPayload) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(payload).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
