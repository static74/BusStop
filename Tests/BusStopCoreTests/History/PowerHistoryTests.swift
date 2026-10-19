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
}
