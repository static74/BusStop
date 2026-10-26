import BusStopCore
import Foundation
import Testing
@testable import BusStopUI

@MainActor
@Suite("Power chart data")
struct PowerChartDataTests {
    private let start = Date(timeIntervalSince1970: 1_791_115_200)

    private func sample(_ seconds: TimeInterval, input: Int? = 30_000, load: Int? = nil,
                        ports: [String: Int] = [:]) -> PowerSample {
        PowerSample(date: start.addingTimeInterval(seconds), systemInputMilliwatts: input,
                    systemLoadMilliwatts: load, portMilliwatts: ports)
    }

    @Test func seriesBreakAcrossSleep() {
        // Two minutes of saved power, an hour asleep, then two more.
        let samples = [0.0, 60, 3_660, 3_720].map { sample($0, ports: ["2/1": 4_500]) }
        let maxGap = PowerRange.hour.maxGap

        let system = PowerChartData.systemPoints(samples, maxGap: maxGap)
        #expect(system.map(\.segment) == [0, 0, 1, 1])
        let ports = PowerChartData.portSeries(samples, title: { _ in "Left" }, maxGap: maxGap)
        #expect(ports.domain == ["Left"])
        #expect(ports.points.map(\.segment) == [0, 0, 1, 1])
        #expect(PowerChartData.isolated(system).isEmpty)
        // A lone minute between gaps gets a dot, since a line cannot show it.
        let lone = [0.0, 60, 1_800, 3_600].map { sample($0) }
        let lonePoints = PowerChartData.systemPoints(lone, maxGap: maxGap)
        #expect(PowerChartData.isolated(lonePoints).map(\.date) == [start.addingTimeInterval(1_800), start.addingTimeInterval(3_600)])
        // Live samples a few seconds apart stay one line.
        let live = [0.0, 2, 4, 12].map { sample($0) }
        #expect(PowerChartData.systemPoints(live, maxGap: PowerRange.tenMinutes.maxGap).map(\.segment) == [0, 0, 0, 0])
    }

    @Test func systemLoadComesFromTheSamples() {
        let samples = [sample(0, load: 12_000), sample(60, input: nil, load: 14_500), sample(120, load: nil)]
        let points = PowerChartData.systemPoints(samples, maxGap: PowerRange.hour.maxGap)
        let load = points.filter { $0.series == PowerChartData.loadName }
        #expect(load.map(\.watts) == [12, 14.5])
        #expect(points.filter { $0.series == PowerChartData.inputName }.count == 2)
        // Ids stay unique across series, as the chart's ForEach needs.
        #expect(Set(points.map(\.id)).count == points.count)
    }
}
