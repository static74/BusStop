import Foundation

/// A `busstop://` deep link, as widgets build them and the app opens them:
/// `busstop://topology/<page>` opens the topology window on a page and
/// `busstop://port/<type>/<number>` opens it with that port selected.
///
/// URLs arrive from outside the app, so `init?(url:)` accepts only these
/// exact forms and returns nil for anything else.
public enum BusStopLink: Hashable, Sendable {
    /// A topology window page. The raw values are also the
    /// `BUSSTOP_AUTOMATION` `topology:<page>` names.
    public enum Page: String, CaseIterable, Sendable {
        case overview, silhouette, allPorts, devices, power, events, diagnostics
    }

    case page(Page)
    case port(PortKey)

    public static let scheme = "busstop"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .page(let page):
            components.host = "topology"
            components.path = "/" + page.rawValue
        case .port(let key):
            // `PortKey.description` is digits and a slash, all valid in a path.
            components.host = "port"
            components.path = "/" + key.description
        }
        return components.url!
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              components.user == nil, components.password == nil, components.port == nil,
              components.percentEncodedPath.hasPrefix("/"),
              let path = String(components.percentEncodedPath.dropFirst()).removingPercentEncoding
        else { return nil }
        switch components.host {
        case "topology":
            guard let page = Page(rawValue: path) else { return nil }
            self = .page(page)
        case "port":
            // Accepts `2/1` and the percent-encoded `2%2F1`.
            guard let key = PortKey(path), key.description == path else { return nil }
            self = .port(key)
        default:
            return nil
        }
    }
}
