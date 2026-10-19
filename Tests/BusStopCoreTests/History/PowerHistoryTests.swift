import Foundation
import Testing
@testable import BusStopCore

/// The live 10-minute buffer behind the sparklines.
@Suite("Power history")
struct PowerHistoryTests {
    private let start = SupportFixtures.date

    private func sample(_ seconds: TimeInterval, _ milliwatts: Int = 1_000) -> PowerSample {
        PowerSample(date: start.addingTimeInterval(seconds), systemInputMilliwatts: milliwatts)
    }

    @Test func dropsSamplesOlderThanTheWindow() {
        var history = PowerHistory(window: 600)
        for seconds in stride(from: 0.0, through: 700, by: 50) { history.append(sample(seconds)) }
        #expect(history.samples.first?.date == start.addingTimeInterval(100))
        #expect(history.samples.last?.date == start.addingTimeInterval(700))
    }

    @Test func replacesSamplesUnderHalfASecondApart() {
        var history = PowerHistory()
        history.append(sample(0, 1))
        history.append(sample(0.3, 2))
        history.append(sample(1, 3))
        #expect(history.samples.map(\.systemInputMilliwatts) == [2, 3])
    }

    @Test func startsOverWhenTheClockGoesBack() {
        var history = PowerHistory()
        history.append(sample(10, 1))
        history.append(sample(20, 2))
        history.append(sample(5, 3))
        #expect(history.samples.map(\.systemInputMilliwatts) == [3])
    }

    @Test func sampleCarriesSystemLoad() {
        let snapshot = SupportFixtures.snapshot(power: PowerSummary(systemInputMilliwatts: 30_000,
                                                                    systemLoadMilliwatts: 12_500, hasBattery: true))
        #expect(PowerSample(snapshot).systemLoadMilliwatts == 12_500)
        // Samples saved before the field existed still decode.
        let old = Data(#"{"date": 0, "portMilliwatts": {}}"#.utf8)
        #expect((try? JSONDecoder().decode(PowerSample.self, from: old))?.systemLoadMilliwatts == nil)
        #expect((try? JSONDecoder().decode(PowerSample.self, from: old)) != nil)
    }

    @Test func segmentsSplitAtGaps() {
        let dates = [0.0, 10, 20, 200, 210, 1_000].map { start.addingTimeInterval($0) }
        #expect(PowerSample.segments(dates, maxGap: 30) == [0, 0, 0, 1, 1, 2])
        #expect(PowerSample.segments(dates, maxGap: 1_000) == [0, 0, 0, 0, 0, 0])
        #expect(PowerSample.segments([], maxGap: 30).isEmpty)
    }

    @Test func seriesSkipSamplesWithoutAReading() {
        let samples = [PowerSample(date: start, systemInputMilliwatts: 2_000, systemLoadMilliwatts: 9_500,
                                   portMilliwatts: ["2/1": -1_500]),
                       PowerSample(date: start.addingTimeInterval(5), batteryMilliwatts: 500)]
        #expect(samples.systemInputSeries.map(\.watts) == [2])
        #expect(samples.systemLoadSeries.map(\.watts) == [9.5])
        #expect(samples.batterySeries.map(\.date) == [start.addingTimeInterval(5)])
        #expect(samples.portKeys.map(\.description) == ["2/1"])
        #expect(samples.series(for: samples.portKeys[0]).map(\.watts) == [-1.5])
    }
}
