import BusStopCore
import SwiftUI
import WidgetKit

/// The frame every Bus Stop widget shares: a title row, then the widget's
/// content, or the empty and stale notices. States are always written out, so
/// they read in vibrant (monochrome) rendering too.
public struct WidgetChrome<Content: View>: View {
    let title: String
    let symbol: String
    let entry: WidgetTimeline.Entry
    let content: (WidgetPayload) -> Content

    public init(_ title: String, symbol: String, entry: WidgetTimeline.Entry,
                @ViewBuilder content: @escaping (WidgetPayload) -> Content) {
        self.title = title
        self.symbol = symbol
        self.entry = entry
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let payload = entry.payload {
                content(payload)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(entry.state == .stale ? 0.35 : 1)
                    .overlay {
                        if entry.state == .stale {
                            WidgetNotice("Bus Stop isn't running",
                                         detail: "Last updated \(payload.capturedAt.formatted(date: .omitted, time: .shortened))")
                        }
                    }
            } else {
                WidgetNotice("Open Bus Stop", detail: "Your ports show here once Bus Stop is running.")
            }
        }
        .foregroundStyle(Lagoon.textPrimary)
        .containerBackground(for: .widget) { Lagoon.background }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(Lagoon.accent)
                .widgetAccentable()
            Text(title)
            Spacer(minLength: 4)
            if entry.state == .demo { DemoBadge() }
        }
        .lagoonFont(.headline, weight: .semibold)
    }
}

/// A centred message for the empty and stale states.
struct WidgetNotice: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(title).lagoonFont(.title3, weight: .semibold)
            Text(detail)
                .lagoonFont(.callout)
                .foregroundStyle(Lagoon.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
