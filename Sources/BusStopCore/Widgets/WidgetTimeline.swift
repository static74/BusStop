import Foundation

/// Turns the payload into the widgets' timeline: what to show now, and when
/// the data goes stale because the app stopped writing it.
public enum WidgetTimeline {
    /// Data older than this means Bus Stop is not running.
    public static let staleAfter: TimeInterval = 5 * 60

    public enum State: Sendable, Hashable {
        /// No payload yet: "Open Bus Stop".
        case empty
        case live
        /// Demo data, shown with a Demo badge.
        case demo
        /// "Bus Stop isn't running"; the payload is kept so views can show the last data.
        case stale
    }

    public struct Entry: Sendable, Hashable {
        public var date: Date
        public var state: State
        public var payload: WidgetPayload?

        public init(date: Date, state: State, payload: WidgetPayload?) {
            self.date = date
            self.state = state
            self.payload = payload
        }
    }

    /// The entry for `now` and, while the data is fresh, a second one at the
    /// moment it goes stale.
    public static func entries(payload: WidgetPayload?, now: Date) -> [Entry] {
        guard let payload else { return [Entry(date: now, state: .empty, payload: nil)] }
        let staleAt = payload.capturedAt.addingTimeInterval(staleAfter)
        guard now < staleAt else { return [Entry(date: now, state: .stale, payload: payload)] }
        return [
            Entry(date: now, state: payload.isDemo ? .demo : .live, payload: payload),
            Entry(date: staleAt, state: .stale, payload: payload),
        ]
    }
}
