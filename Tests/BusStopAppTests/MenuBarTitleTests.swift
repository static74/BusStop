import BusStopCore
import BusStopUI
import Foundation
import Testing
@testable import BusStopApp

/// The menu bar title with and without a pinned port, its VoiceOver text,
/// and where the pin is stored.
@MainActor
@Suite("Menu bar title", .serialized)
struct MenuBarTitleTests {
    private static func port(link: LinkInfo? = nil, power: PortPower? = nil, connected: Bool = true) -> PhysicalPort {
        PhysicalPort(key: PortKey(type: 2, number: 1), kind: .usbC, number: 1, registryName: "Port-USB-C@1",
                     label: PortLabel(location: "Left Rear", source: .catalog, connector: "USB-C", number: 1),
                     isConnected: connected, link: link, power: power)
    }

    private static let fortyGig = LinkInfo(family: .thunderbolt, generation: "Thunderbolt / USB4",
                                           bitsPerSecond: 40_000_000_000)
    private static let measuredInput = PortPower(direction: .input, milliwatts: 61_000, source: .smc)

    /// Settings in a throwaway defaults suite, removed when `body` returns.
    private func withSettings(_ name: String, _ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
        let suite = "BusStopAppTests.MenuBarTitle.\(name)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        try body(AppSettings(defaults: defaults), defaults)
    }

    /// A running demo store for `scenario`, stopped when `body` returns.
    private func withDemoStore(_ settings: AppSettings, _ scenario: DemoScenario = .studioDesk,
                               _ body: (PortStore) throws -> Void) rethrows {
        settings.demoMode = true
        settings.demoScenario = scenario
        let store = PortStore(settings: settings)
        store.start()
        defer { store.stop() }
        try body(store)
    }

    @Test(arguments: MenuBarTextMode.allCases)
    func titleWithoutPinIsUnchanged(_ mode: MenuBarTextMode) {
        let expected: [MenuBarTextMode: String] = [.both: "5 · 38W", .power: "38W", .devices: "5", .none: ""]
        #expect(StatusItemController.menuBarText(mode: mode, deviceCount: 5, milliwatts: 38_000) == expected[mode])
    }

    @Test func pinnedSegmentShowsMeasuredInput() {
        let port = Self.port(power: Self.measuredInput)
        #expect(StatusItemController.pinnedSegment(port, value: .power, precision: .automatic) == "↓61W")
    }

    @Test func pinnedSegmentMarksBudgetsWithCeiling() {
        let budget = Self.port(power: PortPower(direction: .output, milliwatts: 4_500, source: .usbAllocation))
        #expect(StatusItemController.pinnedSegment(budget, value: .power, precision: .automatic) == "↑≤4.5W")
        let contract = Self.port(power: PortPower(direction: .input, milliwatts: 96_000, source: .pdContract))
        #expect(StatusItemController.pinnedSegment(contract, value: .power, precision: .oneDecimal) == "↓≤96.0W")
    }

    @Test func pinnedSegmentSpeedAndBoth() {
        let port = Self.port(link: Self.fortyGig, power: Self.measuredInput)
        #expect(StatusItemController.pinnedSegment(port, value: .speed, precision: .automatic) == "40G")
        #expect(StatusItemController.pinnedSegment(port, value: .both, precision: .automatic) == "40G ↓61W")
        // A link with an unknown rate (DisplayPort without a lane count) leaves only the power.
        let display = Self.port(link: LinkInfo(family: .displayPort, generation: "DisplayPort"),
                                power: Self.measuredInput)
        #expect(StatusItemController.pinnedSegment(display, value: .both, precision: .automatic) == "↓61W")
    }

    @Test func emptyPinnedPortShowsPlaceholder() {
        let empty = Self.port(connected: false)
        for value in PinnedPortValue.allCases {
            #expect(StatusItemController.pinnedSegment(empty, value: value, precision: .automatic) == "–")
        }
    }

    @Test func titleJoinsTextAndPin() throws {
        try withSettings("join") { settings, _ in
            try withDemoStore(settings) { store in
                let snapshot = store.snapshot
                let port = try #require(snapshot.ports.first { $0.label.title == "Left Center · USB-C" })
                settings.menuBarText = .devices
                settings.menuBarPinnedValue = .speed
                #expect(StatusItemController.menuBarTitle(snapshot: snapshot, settings: settings,
                                                          pinnedKey: port.key) == "\(snapshot.deviceCount) · 80G")
                settings.menuBarText = .none
                #expect(StatusItemController.menuBarTitle(snapshot: snapshot, settings: settings,
                                                          pinnedKey: port.key) == "80G")
            }
        }
    }

    @Test func missingPinnedKeyContributesNothing() {
        withSettings("missing") { settings, _ in
            withDemoStore(settings) { store in
                let missing = PortKey(type: 2, number: 42)
                store.pinPort(missing)
                let snapshot = store.snapshot
                #expect(StatusItemController.menuBarTitle(snapshot: snapshot, settings: settings,
                                                          pinnedKey: store.pinnedPortKey)
                        == StatusItemController.menuBarTitle(snapshot: snapshot, settings: settings, pinnedKey: nil))
                #expect(store.pinnedPortKey == missing)
            }
        }
    }

    @Test func pinIsStoredPerModel() throws {
        try withSettings("perModel") { settings, _ in
            settings.menuBarPinnedPorts = ["Mac17,9": "17/1"]
            try withDemoStore(settings) { store in
                #expect(store.snapshot.machine.model == "Mac17,9")
                // The live Mac's pin does not show in the demo.
                #expect(store.pinnedPortKey == nil)
                let key = try #require(store.snapshot.ports.first?.key)
                store.pinPort(key)
                #expect(settings.menuBarPinnedPorts == ["Mac17,9": "17/1", "demo:Mac17,9": key.description])
                #expect(store.pinnedPortKey == key)
                store.pinPort(nil)
                #expect(settings.menuBarPinnedPorts == ["Mac17,9": "17/1"])
            }
        }
    }

    @Test func accessibilityDescriptionNamesPinnedPort() {
        let port = Self.port(link: Self.fortyGig, power: Self.measuredInput)
        #expect(StatusItemController.accessibilityDescription(hasLoaded: true, deviceCount: 5, milliwatts: 38_000,
                                                              pinned: port)
                == "Bus Stop: 5 devices, 38 W. Pinned: Left Rear USB-C, 40 gigabits per second, 61 watts in")
        #expect(StatusItemController.accessibilityDescription(hasLoaded: true, deviceCount: 1, milliwatts: nil,
                                                              pinned: Self.port(connected: false))
                == "Bus Stop: 1 device. Pinned: Left Rear USB-C, nothing connected")
        #expect(StatusItemController.accessibilityDescription(hasLoaded: true, deviceCount: 5, milliwatts: 38_000,
                                                              pinned: nil)
                == "Bus Stop: 5 devices, 38 W")
    }

    @Test func portAccessibilityLabelSaysPinned() {
        let port = Self.port(connected: false)
        #expect(PopoverText.portAccessibilityLabel(port, isPinned: false) == "Left Rear USB-C port, nothing connected")
        #expect(PopoverText.portAccessibilityLabel(port, isPinned: true)
                == "Left Rear USB-C port, nothing connected, pinned to the menu bar")
    }

    @Test func cardAndMenuBarSpeakPowerTheSameWay() {
        let budget = PortPower(direction: .output, milliwatts: 4_500, source: .usbAllocation)
        #expect(PopoverText.spokenPortPower(budget) == "up to 4.5 watts")
        #expect(PopoverText.spokenPortPower(Self.measuredInput) == "61 watts in")
        #expect(PopoverText.spokenPortPower(nil) == nil)
        #expect(PopoverText.portAccessibilityLabel(Self.port(power: budget), isPinned: false).hasSuffix(", up to 4.5 watts"))
    }

    @Test func pinSettingsRoundTripAndReset() {
        withSettings("roundTrip") { settings, defaults in
            #expect(settings.menuBarPinnedPorts.isEmpty)
            #expect(settings.menuBarPinnedValue == .both)
            settings.menuBarPinnedPorts = ["Mac17,9": "2/1"]
            settings.menuBarPinnedValue = .speed

            let reread = AppSettings(defaults: defaults)
            #expect(reread.menuBarPinnedPorts == ["Mac17,9": "2/1"])
            #expect(reread.menuBarPinnedValue == .speed)

            reread.resetAll()
            #expect(reread.menuBarPinnedPorts.isEmpty)
            #expect(reread.menuBarPinnedValue == .both)
            #expect(AppSettings.Key.all.contains(AppSettings.Key.menuBarPinnedPorts))
            #expect(AppSettings.Key.all.contains(AppSettings.Key.menuBarPinnedValue))
            #expect(AppSettings(defaults: defaults).menuBarPinnedPorts.isEmpty)
        }
    }
}
