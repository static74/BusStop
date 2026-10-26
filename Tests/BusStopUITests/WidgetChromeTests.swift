import BusStopCore
import SwiftUI
import Testing
@testable import BusStopUI

@Suite("Widget chrome")
@MainActor
struct WidgetChromeTests {
    typealias S = WidgetTestSupport

    @Test(arguments: [WidgetTimeline.State.empty, .live, .demo, .stale])
    func drawsEveryState(_ state: WidgetTimeline.State) throws {
        let entry = state == .empty
            ? WidgetTimeline.Entry(date: S.date, state: .empty, payload: nil)
            : S.entry(.studioDesk, state: state)
        let view = WidgetChrome("Ports", symbol: "cable.connector", entry: entry) { payload in
            Text("\(payload.snapshot.ports.count) ports")
        }
        for family in S.Family.allCases {
            #expect(S.hasContent(try S.render(view, family), fraction: 0.001), "\(state) \(family)")
        }
    }

    @Test func demoPayloadHasEvents() {
        #expect(!S.payload(.flakyCable).events.isEmpty)
        #expect(S.payload(.studioDesk).recentPower.count == 120)
    }
}
