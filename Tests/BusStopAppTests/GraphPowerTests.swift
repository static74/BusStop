import CoreGraphics
import Testing
@testable import BusStopApp

@Suite("Map power mode")
struct GraphPowerTests {
    @Test func tiersStepAtFiveFifteenAndFortyFiveWatts() {
        #expect([0, 1, 4_999, 5_000, 14_999, 15_000, 44_999, 45_000, 140_000].map(PowerTier.init(milliwatts:))
                == [.none, .under5, .under5, .under15, .under15, .under45, .under45, .high, .high])
    }

    @Test func budgetsAreMarkedAsCeilings() {
        #expect(GraphEdgePower(milliwatts: 47_000, flowsToParent: true, isMeasured: true).label == "47 W")
        #expect(GraphEdgePower(milliwatts: 4_500, flowsToParent: false, isMeasured: false).label.hasPrefix("≤"))
    }

    @Test func reversedCurveRunsTheOtherWay() {
        let curve = GraphCurve(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 40))
        #expect(curve.reversed.start == curve.end && curve.reversed.end == curve.start)
        #expect(curve.reversed.point(at: 0.25) == curve.point(at: 0.75))
    }
}
