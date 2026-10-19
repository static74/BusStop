import Testing
@testable import BusStopCore

/// The short forms the menu bar shows.
@Suite("Compact formats")
struct FormatTests {
    @Test func compactDataRateDropsUnitsAndSpaces() {
        let cases: [(Int64, String)] = [
            (120_000_000_000, "120G"), (80_000_000_000, "80G"), (40_000_000_000, "40G"),
            (10_000_000_000, "10G"), (5_000_000_000, "5G"), (480_000_000, "480M"),
            (12_000_000, "12M"), (1_500_000, "1.5M"),
        ]
        for (bps, expected) in cases {
            #expect(Format.compactDataRate(bitsPerSecond: bps) == expected)
        }
    }

    @Test func compactPowerAutomatic() {
        #expect(Format.compactPower(milliwatts: 38_000) == "38W")
        #expect(Format.compactPower(milliwatts: 4_500) == "4.5W")
        #expect(Format.compactPower(milliwatts: 90) == "90mW")
        #expect(Format.compactPower(milliwatts: 0) == "0W")
    }

    @Test func compactPowerForcedDecimals() {
        #expect(Format.compactPower(milliwatts: 38_200, decimals: 0) == "38W")
        #expect(Format.compactPower(milliwatts: 4_500, decimals: 0) == "5W")
        #expect(Format.compactPower(milliwatts: 38_200, decimals: 1) == "38.2W")
        #expect(Format.compactPower(milliwatts: 4_500, decimals: 1) == "4.5W")
    }
}
