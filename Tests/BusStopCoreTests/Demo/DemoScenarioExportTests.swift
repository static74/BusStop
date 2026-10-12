import Foundation
import Testing
@testable import BusStopCore

@Suite("Demo scenarios: determinism and variation")
struct DemoScenarioVariationTests {
    typealias S = DemoTestSupport

    @Test(arguments: DemoScenario.allCases)
    func sameTickSameCapture(_ scenario: DemoScenario) throws {
        for tick in [0, 1, 17, 1_000, -3] {
            let raw = scenario.raw(at: S.date, tick: tick)
            #expect(raw == scenario.raw(at: S.date, tick: tick))
            #expect(try Exporter.rawJSON(raw, redact: false) == Exporter.rawJSON(scenario.raw(at: S.date, tick: tick),
                                                                                    redact: false))
            #expect(S.snapshot(scenario, tick: tick) == S.snapshot(scenario, tick: tick))
        }
        #expect(scenario.raw(at: S.date).capturedAt == S.date)
        #expect(scenario.raw(at: S.date).machine.model == scenario.model)
    }

    /// Only power readings change from tick to tick: the registry records,
    /// the device trees, labels, displays and diagnostics stay put.
    @Test(arguments: DemoScenario.allCases)
    func onlyPowerReadingsVary(_ scenario: DemoScenario) {
        let first = scenario.raw(at: S.date, tick: 0)
        let base = S.withoutPowerReadings(S.snapshot(scenario, tick: 0))
        for tick in [1, 2, 9, 30, 101, 4_321] {
            let raw = scenario.raw(at: S.date, tick: tick)
            #expect(raw.portNodes == first.portNodes)
            #expect(raw.usbDevices == first.usbDevices)
            #expect(raw.thunderboltSwitches == first.thunderboltSwitches)
            #expect(raw.displays == first.displays)
            #expect(raw.adapter == first.adapter)
            #expect(raw.portControllerUUIDs == first.portControllerUUIDs)
            #expect(raw.smcChannels.map(\.uuid) == first.smcChannels.map(\.uuid))
            #expect(S.withoutPowerReadings(S.snapshot(scenario, tick: tick)) == base)
            // Moving power numbers never produce connection events.
            #expect(SnapshotDiffer.events(from: S.snapshot(scenario, tick: 0), to: S.snapshot(scenario, tick: tick),
                                          at: S.date).isEmpty)
        }
    }

    @Test func powerReadingsMoveWithinBounds() throws {
        var studioInputs = Set<Int>()
        for tick in 0..<240 {
            let studio = S.snapshot(.studioDesk, tick: tick)
            let input = try #require(studio.power.systemInputMilliwatts)
            studioInputs.insert(input)
            #expect(S.isNear(input, 62_000, within: 0.03))
            #expect(S.isNear(studio.port(PortKey(type: 2, number: 2))?.power?.milliwatts, 3_950, within: 0.035))
            #expect(S.isNear(studio.port(PortKey(type: 17, number: 1))?.power?.milliwatts, 62_000, within: 0.031))
            #expect((studio.power.battery?.powerMilliwatts ?? 0) > 0)

            let travel = S.snapshot(.travel, tick: tick)
            #expect(S.isNear(travel.power.systemInputMilliwatts, 31_200, within: 0.03))
            #expect(S.isNear(travel.port(PortKey(type: 2, number: 2))?.power?.milliwatts, 4_500, within: 0.035))

            let dock = S.snapshot(.dockStation, tick: tick)
            #expect(S.isNear(dock.port(PortKey(type: 2, number: 3))?.power?.milliwatts, 1_150, within: 0.04))
            #expect(dock.port(PortKey(type: 2, number: 1))?.power?.milliwatts == 4_480)

            let unplugged = S.snapshot(.unplugged, tick: tick)
            #expect(S.isNear(unplugged.power.systemLoadMilliwatts, 9_100, within: 0.05))
        }
        // The sparkline moves: many distinct readings, smooth from tick to tick.
        #expect(studioInputs.count > 100)
        for tick in 0..<240 {
            let now = try #require(S.snapshot(.studioDesk, tick: tick).power.systemInputMilliwatts)
            let next = try #require(S.snapshot(.studioDesk, tick: tick + 1).power.systemInputMilliwatts)
            #expect(abs(next - now) < 1_000)
        }
    }

    @Test func waveStaysWithinItsAmplitude() {
        for tick in [-1_000_000, -1, 0, 1, 12, 37, 1_000_000, Int.max, Int.min] {
            let factor = DemoWave(tick: tick).factor(amplitude: 0.03, phase: 0.4)
            #expect(factor.isFinite)
            #expect(abs(factor - 1) <= 0.03 + 1e-12)
        }
    }
}

@Suite("Demo scenarios: export")
struct DemoScenarioExportTests {
    typealias S = DemoTestSupport

    /// Serial numbers and similar values the demo data carries.
    static let serials = ["S7MPNS0X104823L", "E0D55EA574A3F4C0B8640134", "00008150-001A2C3E1E40801C",
                          "S6NPNS0W512893K", "C4H3271027Q1F4MAN", "C4H3504001J1LXGAH"]

    @Test(arguments: DemoScenario.allCases)
    func textTree(_ scenario: DemoScenario) {
        let snapshot = S.snapshot(scenario)
        let tree = Exporter.textTree(snapshot)
        #expect(tree.hasPrefix(snapshot.machine.name + " · macOS 27.0 · demo\n"))
        #expect(tree.hasSuffix("\n"))
        for port in snapshot.ports {
            #expect(tree.contains(port.label.title))
        }
        for (device, _, _) in snapshot.allDevices {
            #expect(tree.contains(device.name))
        }
        #expect(!tree.split(separator: "\n").contains { $0.hasSuffix(" ") })
    }

    @Test func studioDeskTextTree() {
        let tree = Exporter.textTree(S.snapshot(.studioDesk))
        // Printed so the tree can be reviewed in the test log.
        print(tree)
        let expected = """
            MacBook Pro (14-inch, 2026, M5 Pro) · macOS 27.0 · demo
            Power: 140W USB-C Power Adapter · 28 V × 5 A · 62 W in · Charging · 76% · 4 W to ports
            ├─ Left Rear · MagSafe   140W USB-C Power Adapter   ↓ 62 W
            ├─ Left Center · USB-C   USB4 v2 / TB5 @ 80 Gb/s
            │  └─ Studio Display XDR · 80 Gb/s
            │     └─ Studio Display XDR Hub · 10 Gb/s
            │        ├─ PSSD T9 · 10 Gb/s · 4.5 W
            │        └─ Studio Display XDR Camera · 480 Mb/s · 2.5 W
            ├─ Left Front · USB-C   USB 3.2 Gen 2 @ 10 Gb/s   ↑ 4 W
            │  └─ USB3.1 Hub · 10 Gb/s · 4 W
            │     ├─ DataTraveler 3.0 · 480 Mb/s · 2.5 W
            │     ├─ Keychron K8 Pro · 12 Mb/s · 0.5 W
            │     └─ USB Optical Mouse · 1.5 Mb/s · 0.5 W
            ├─ Right Rear · HDMI   (empty)
            └─ Right Center · USB-C   (empty)

            Displays
            ├─ Built-in Liquid Retina XDR Display · 3024 × 1964 @ 120 Hz · built-in
            └─ Studio Display XDR · 5120 × 2880 @ 120 Hz · Left Center · USB-C

            Diagnostics
            └─ Warning: DataTraveler 3.0 is running at USB 2 speed

            """
        #expect(tree == expected)
    }

    @Test(arguments: DemoScenario.allCases)
    func jsonRoundTrips(_ scenario: DemoScenario) throws {
        let snapshot = S.snapshot(scenario)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plain = try Exporter.json(snapshot, redact: false)
        #expect(try decoder.decode(HostSnapshot.self, from: plain) == snapshot)

        let redacted = try Exporter.json(snapshot)
        let text = String(decoding: redacted, as: UTF8.self)
        #expect(Self.serials.allSatisfy { !text.contains($0) })
        #expect(try decoder.decode(HostSnapshot.self, from: redacted) == Exporter.redacted(snapshot))
    }

    @Test(arguments: DemoScenario.allCases)
    func markdownReport(_ scenario: DemoScenario) {
        let snapshot = S.snapshot(scenario)
        let report = Exporter.markdown(snapshot)
        #expect(report.contains(snapshot.machine.name))
        #expect(report.contains("demo data"))
        for port in snapshot.ports {
            #expect(report.contains(port.label.title))
        }
        #expect(Self.serials.allSatisfy { !report.contains($0) })
    }

    @Test(arguments: DemoScenario.allCases)
    func rawCaptureRoundTrips(_ scenario: DemoScenario) throws {
        let raw = scenario.raw(at: S.date, tick: 5)
        #expect(try Exporter.decodeRaw(Exporter.rawJSON(raw, redact: false)) == raw)
        let redacted = try Exporter.rawJSON(raw)
        #expect(Self.serials.allSatisfy { !String(decoding: redacted, as: UTF8.self).contains($0) })
        // A redacted capture still builds the same ports and device trees.
        let rebuilt = TopologyBuilder.build(try Exporter.decodeRaw(redacted), options: BuildOptions(isDemo: true))
        #expect(rebuilt.ports.map(\.label.title) == S.snapshot(scenario, tick: 5).ports.map(\.label.title))
        #expect(rebuilt.deviceCount == S.snapshot(scenario, tick: 5).deviceCount)
    }

    @Test func scenarioMetadata() {
        #expect(DemoScenario.allCases.map(\.title) == ["Studio desk", "Travel", "Dock station", "Unplugged"])
        #expect(DemoScenario.allCases.map(\.model) == ["Mac17,9", "Mac16,12", "Mac16,11", "Mac17,2"])
        #expect(DemoScenario.allCases.allSatisfy { !$0.summary.isEmpty && $0.id == $0.rawValue })
        #expect(DemoScenario.allCases.allSatisfy { PortLocationCatalog.entry(for: $0.model) != nil })
    }
}
