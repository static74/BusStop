import Foundation
import Testing
@testable import BusStopCore

@Suite("Connection health")
struct ConnectionHealthTests {
    typealias F = HealthFixtures

    // MARK: Raised

    @Test func driveSeenAt480AfterTenGigabitIsASpeedRegression() throws {
        var run = HealthRun()
        run.observe(0, [F.port(1, [F.drive()])])
        run.observe(20, [F.port(1, [F.drive()])])
        #expect(run.last.isEmpty)
        // The drive comes back on the USB 2 controller and reports bcdUSB 0x0210,
        // so the usb2Fallback rule cannot see it.
        let slow = F.drive(location: 0x0010_0000, bps: 480_000_000, version: "2.1")
        run.observe(30, [F.port(1, [slow])])
        let finding = try #require(run.last.first)
        #expect(run.kinds() == [.speedRegression])
        #expect(finding.id == "speedRegression:\(slow.id)")
        #expect(finding.severity == .warning)
        #expect(finding.deviceID == slow.id)
        #expect(finding.portKey == F.port1)
        #expect(finding.title == "Samsung T9 is running slower than before")
        #expect(finding.detail.contains("480 Mb/s"))
        #expect(finding.detail.contains("10 Gb/s"))

        // Back at full speed, the finding clears.
        run.observe(40, [F.port(1, [F.drive()])])
        #expect(run.last.isEmpty)
    }

    @Test func threeCyclesOnOnePortBlameTheCable() throws {
        var run = HealthRun()
        run.observe(0, [F.port(1)])
        run.cycle(F.drive(), on: 1, times: 2, from: 20)
        #expect(run.last.isEmpty)
        run.observe(45, [F.port(1)])
        run.observe(50, [F.port(1, [F.drive()])])
        let finding = try #require(run.last.first)
        #expect(run.kinds() == [.flakyConnection])
        #expect(finding.id == "flakyConnection:\(F.drive().id)")
        #expect(finding.title == "Samsung T9 keeps disconnecting")
        #expect(finding.detail.contains("came back 3 times in the last 10 minutes"))
        #expect(finding.detail.contains("Likely cause: the cable."))
        #expect(finding.portKey == F.port1)

        let history = try #require(run.health.history(ofDevice: F.drive().id))
        #expect(history.cycles == 3)
        #expect(history.culprit == .cable)
        #expect(history.bestLink?.bitsPerSecond == 10_000_000_000)
    }

    @Test func cyclesOnTwoPortsBlameTheDevice() throws {
        var run = HealthRun()
        run.observe(0, [F.port(1), F.port(2)])
        let onPort2 = F.drive(location: 0x0210_0000)
        run.cycle(F.drive(), on: 1, times: 2, from: 20)
        run.observe(45, [F.port(1), F.port(2)])
        run.observe(50, [F.port(1), F.port(2, [onPort2])])
        #expect(run.last.isEmpty)
        run.observe(55, [F.port(1), F.port(2)])
        run.observe(60, [F.port(1), F.port(2, [onPort2])])
        let finding = try #require(run.last.first)
        #expect(finding.kind == .flakyConnection)
        #expect(finding.detail.contains("Likely cause: the device."))
        #expect(finding.suggestion?.contains("more than one port") == true)
    }

    @Test func threeDevicesCyclingOnOnePortBlameThePort() throws {
        var run = HealthRun()
        let a = F.usb("Drive A", location: 0x0110_0000, serial: "A-1")
        let b = F.usb("Drive B", location: 0x0110_0000, serial: "B-2")
        let c = F.usb("Drive C", location: 0x0110_0000, serial: "C-3")
        let aOnPort2 = F.usb("Drive A", location: 0x0210_0000, serial: "A-1")
        run.observe(0, [F.port(1, liquid: true)])
        var t = run.cycle(a, on: 1, times: 3, from: 20)
        #expect(run.last.first?.detail.contains("the cable") == true)
        // Drive A moves to port 2 and is fine there; B and C each arrive on port 1, then drop three times too.
        for device in [b, c] {
            for _ in 0..<4 {
                run.observe(t + 5, [F.port(1, liquid: true), F.port(2, [aOnPort2])])
                run.observe(t + 10, [F.port(1, [device], liquid: true), F.port(2, [aOnPort2])])
                t += 10
            }
        }
        let finding = try #require(run.last.first)
        #expect(run.kinds() == [.flakyConnection])
        #expect(finding.id == "flakyConnection:port:2/1")
        #expect(finding.title == "Devices keep disconnecting from Left Rear · USB-C")
        #expect(finding.detail.contains("3 devices"))
        #expect(finding.detail.contains("Likely cause: the port."))
        #expect(finding.detail.contains("liquid"))
        #expect(finding.deviceID == nil)
    }

    @Test func hubChildrenCyclingTogetherBlameTheHub() throws {
        let keyboard = F.usb("Keyboard", location: 0x0111_0000, bps: 12_000_000, version: "2.0", kind: .keyboard,
                             vendorID: 0x05ac, productID: 0x024f)
        let mouse = F.usb("Mouse", location: 0x0112_0000, bps: 12_000_000, version: "2.0", kind: .mouse,
                          vendorID: 0x046d, productID: 0xc077)
        func hub(_ children: [DeviceNode]) -> DeviceNode {
            F.usb("USB hub", location: 0x0110_0000, kind: .hub, selfPowered: false, children: children)
        }
        var run = HealthRun()
        run.observe(0, [F.port(1, [hub([keyboard, mouse])])])
        for i in 0..<3 {
            let t = 20 + Double(i) * 10
            run.observe(t, [F.port(1, [hub([keyboard, mouse])])])
            run.observe(t + 5, [F.port(1, [hub([])])])
        }
        run.observe(50, [F.port(1, [hub([keyboard, mouse])])])
        let finding = try #require(run.last.first)
        #expect(run.kinds() == [.flakyConnection])
        #expect(finding.id == "flakyConnection:\(hub([]).id)")
        #expect(finding.title == "Devices behind USB hub keep disconnecting")
        #expect(finding.detail.contains("Likely cause: the hub."))
        #expect(finding.detail.contains("no power supply of its own"))
        #expect(finding.deviceID == hub([]).id)
    }

    @Test func aNeighbourRepluggedOnceDoesNotShiftTheBlameToTheHub() throws {
        let keyboard = F.usb("Keyboard", location: 0x0111_0000, bps: 12_000_000, version: "2.0", kind: .keyboard,
                             vendorID: 0x05ac, productID: 0x024f)
        let mouse = F.usb("Mouse", location: 0x0112_0000, bps: 12_000_000, version: "2.0", kind: .mouse,
                          vendorID: 0x046d, productID: 0xc077)
        func hub(_ children: [DeviceNode]) -> DeviceNode {
            F.usb("USB hub", location: 0x0110_0000, kind: .hub, selfPowered: true, children: children)
        }
        var run = HealthRun()
        run.observe(0, [F.port(1, [hub([keyboard, mouse])])])
        // The mouse is unplugged and plugged back once; the keyboard drops three times.
        run.observe(15, [F.port(1, [hub([keyboard])])])
        run.observe(18, [F.port(1, [hub([keyboard, mouse])])])
        for i in 0..<3 {
            let t = 20 + Double(i) * 10
            run.observe(t + 5, [F.port(1, [hub([mouse])])])
            run.observe(t + 10, [F.port(1, [hub([keyboard, mouse])])])
        }
        let finding = try #require(run.last.first)
        #expect(run.kinds() == [.flakyConnection])
        #expect(finding.id == "flakyConnection:\(keyboard.id)")
        #expect(finding.detail.contains("Likely cause: the cable."))
    }

    @Test func threeReversalsAreLinkFlapping() throws {
        var run = HealthRun()
        run.observe(0, [F.port(1, [F.drive()])])
        for (i, bps) in [5_000_000_000, 10_000_000_000, 5_000_000_000, 10_000_000_000].enumerated() {
            run.observe(20 + Double(i) * 10, [F.port(1, [F.drive(bps: Int64(bps))])])
        }
        let finding = try #require(run.last.first { $0.kind == .linkFlapping })
        #expect(finding.title == "Samsung T9 keeps changing speed")
        #expect(finding.detail.contains("3 times"))
        #expect(!run.kinds().contains(.flakyConnection))
    }

    @Test func plugEventCountRevealsFastCycles() throws {
        var run = HealthRun()
        run.observe(0, [F.port(1, [F.drive()], plugEvents: 10)])
        run.observe(20, [F.port(1, [F.drive()], plugEvents: 10)])
        run.observe(30, [F.port(1, [F.drive()], plugEvents: 14)])
        #expect(run.last.isEmpty)
        run.observe(40, [F.port(1, [F.drive()], plugEvents: 16)])
        #expect(run.kinds() == [.flakyConnection])
        // A counter that goes down starts over and adds nothing.
        var reset = HealthRun()
        reset.observe(0, [F.port(1, [F.drive()], plugEvents: 100)])
        reset.observe(20, [F.port(1, [F.drive()], plugEvents: 4)])
        reset.observe(30, [F.port(1, [F.drive()], plugEvents: 6)])
        #expect(reset.health.history(ofDevice: F.drive().id)?.cycles == 1)
        // A glitched reading adds no more than a finding needs.
        var glitch = HealthRun()
        glitch.observe(0, [F.port(1, [F.drive()], plugEvents: 13)])
        glitch.observe(20, [F.port(1, [F.drive()], plugEvents: Int(UInt32.max))])
        #expect(glitch.health.history(ofDevice: F.drive().id)?.cycles == ConnectionHealth.threshold)
    }

    @Test func findingHoldsUntilTheWindowIsQuiet() {
        var run = HealthRun()
        run.observe(0, [F.port(1)])
        let last = run.cycle(F.drive(), on: 1, times: 3, from: 20)
        #expect(run.kinds() == [.flakyConnection])
        // The first cycle (at 30 s) has left the window, so only two remain; the finding holds.
        run.observe(30 + ConnectionHealth.window + 1, [F.port(1, [F.drive()])])
        #expect(run.kinds() == [.flakyConnection])
        run.observe(last + ConnectionHealth.window + 1, [F.port(1, [F.drive()])])
        #expect(run.last.isEmpty)
    }

    @Test func cyclesWhileTheScreensSleepAreCounted() {
        // Captures only at each change, a minute apart, with no gap in between.
        var run = HealthRun()
        run.observe(0, [F.port(1, [F.drive()])])
        for i in 0..<3 {
            let t = 100 + Double(i) * 120
            run.observe(t, [F.port(1)])
            run.observe(t + 60, [F.port(1, [F.drive()])])
        }
        #expect(run.kinds() == [.flakyConnection])
    }

    @Test func leafDeviceUnpluggedLikeDemoWatchRaisesAFlakyFinding() {
        // `busstop --watch --demo studioDesk`: the last leaf USB device is out for two 2 s ticks in every four.
        var health = ConnectionHealth()
        var findings: [Diagnostic] = []
        for tick in 0..<40 {
            var raw = DemoScenario.studioDesk.raw(at: F.start.addingTimeInterval(Double(tick) * 2), tick: tick)
            if (tick / 2) % 2 == 1 {
                let parents = Set(raw.usbDevices.compactMap(\.parentDeviceID))
                let leaf = raw.usbDevices.last { !parents.contains($0.id) }?.id
                raw.usbDevices.removeAll { $0.id == leaf }
            }
            let snapshot = TopologyBuilder.build(raw, options: BuildOptions(isDemo: true))
            findings = health.observe(snapshot, afterGap: tick == 0)
        }
        #expect(findings.map(\.kind).contains(.flakyConnection))
    }

    @Test func flakyCableScenarioRaisesAFlakyFinding() throws {
        var health = ConnectionHealth()
        var firstRaised: Int?
        var findings: [Diagnostic] = []
        for tick in 0..<25 {
            let raw = DemoScenario.flakyCable.raw(at: F.start.addingTimeInterval(Double(tick) * 2), tick: tick)
            let snapshot = TopologyBuilder.build(raw, options: BuildOptions(isDemo: true))
            findings = health.observe(snapshot, afterGap: tick == 0)
            if firstRaised == nil, !findings.isEmpty { firstRaised = tick }
        }
        // Drops in the first 15 s are ignored, so the third counted cycle comes back on tick 19.
        #expect(firstRaised == 19)
        let finding = try #require(findings.first)
        #expect(finding.kind == .flakyConnection)
        #expect(finding.title == "iPhone keeps disconnecting")
        #expect(finding.detail.contains("Likely cause: the cable."))
    }

    // MARK: Quiet

    @Test func bandwidthBoostIsNotFlapping() {
        let symmetric = LinkInfo(family: .thunderbolt, generation: "USB4 v2 / TB5", bitsPerSecond: 80_000_000_000,
                                 lanes: 2)
        let boost = LinkInfo(family: .thunderbolt, generation: "USB4 v2 / TB5", bitsPerSecond: 120_000_000_000,
                             lanes: 3, isAsymmetric: true)
        var run = HealthRun()
        for i in 0..<8 {
            let display = DeviceNode(id: "tb:5d1", bus: .thunderbolt, kind: .display, name: "Studio Display XDR",
                                     link: i % 2 == 0 ? symmetric : boost)
            run.observe(Double(i) * 20, [F.port(1, [display])])
        }
        #expect(run.last.isEmpty)
    }

    @Test func displayPortRetrainingIsNotFlapping() {
        var run = HealthRun()
        for i in 0..<8 {
            let link = LinkInfo(family: .displayPort, generation: "DisplayPort",
                                bitsPerSecond: i % 2 == 0 ? 32_400_000_000 : 21_600_000_000, lanes: 4)
            let display = DeviceNode(id: "display:610:a04f:1", bus: .displayPort, kind: .display, name: "LG",
                                     link: link)
            run.observe(Double(i) * 20, [F.port(1, [display])])
        }
        #expect(run.last.isEmpty)
    }

    @Test func wakeReEnumerationIsIgnored() {
        var run = HealthRun()
        run.observe(0, [F.port(1, [F.drive()])])
        run.observe(100, [F.port(1, [F.drive()])])
        // After wake, the drive comes and goes while the bus settles.
        run.observe(1_000, [F.port(1)], afterGap: true)
        for t in stride(from: 1_003.0, to: 1_015, by: 6) {
            run.observe(t, [F.port(1, [F.drive()])])
            run.observe(t + 3, [F.port(1)])
        }
        run.observe(1_016, [F.port(1, [F.drive()])])
        #expect(run.last.isEmpty)
        #expect(run.health.history(ofDevice: F.drive().id)?.cycles == 0)
    }

    @Test func linkTrainingAroundWakeIsNotFlapping() {
        var run = HealthRun()
        run.observe(0, [F.port(1, [F.drive()])])
        run.observe(100, [F.port(1, [F.drive(bps: 5_000_000_000)])])
        // After wake the link trains up and down while the bus settles, then once more after it.
        run.observe(1_000, [F.port(1, [F.drive(bps: 5_000_000_000)])], afterGap: true)
        run.observe(1_005, [F.port(1, [F.drive()])])
        run.observe(1_010, [F.port(1, [F.drive(bps: 5_000_000_000)])])
        run.observe(1_020, [F.port(1, [F.drive()])])
        #expect(!run.kinds().contains(.linkFlapping))
    }

    @Test func movesBetweenPortsOfDifferentSpeedsAreNotFlapping() {
        // No capture catches the drive away between ports.
        var run = HealthRun()
        let slow = F.drive(location: 0x0210_0000, bps: 5_000_000_000)
        for i in 0..<6 {
            run.observe(Double(i) * 20, i.isMultiple(of: 2) ? [F.port(1, [F.drive()]), F.port(2)]
                                                            : [F.port(1), F.port(2, [slow])])
        }
        #expect(run.last.isEmpty)
    }

    @Test func dockPlugInOverThreeCapturesIsQuiet() {
        let ssd = F.usb("Dock SSD", location: 0x0111_0000, serial: "SSD-1")
        func dock(_ children: [DeviceNode]) -> DeviceNode {
            DeviceNode(id: "tb:d0c", bus: .thunderbolt, kind: .dock, name: "Dock", children: children)
        }
        var run = HealthRun()
        run.observe(0, [F.port(1)])
        // The dock's USB side flickers while it enumerates, a quarter second apart.
        let stages: [[DeviceNode]] = [[], [ssd], [], [ssd], [], [ssd], [], [ssd]]
        for (i, children) in stages.enumerated() {
            run.observe(20 + Double(i) * 0.3, [F.port(1, [dock(children)])])
        }
        #expect(run.last.isEmpty)
        #expect(run.health.history(ofDevice: ssd.id)?.cycles == 0)
    }

    @Test func twoIdenticalKeyboardsAreNotMerged() throws {
        // Same vendor, product and serial: identity falls back to port and route,
        // so the keyboard that drops is told apart from the one that stays.
        let steady = F.usb("Keyboard", location: 0x0110_0000, serial: "0001", kind: .keyboard)
        let dropping = F.usb("Keyboard", location: 0x0210_0000, serial: "0001", kind: .keyboard)
        var run = HealthRun()
        run.observe(0, [F.port(1, [steady]), F.port(2)])
        for i in 0..<3 {
            let t = 20 + Double(i) * 10
            run.observe(t, [F.port(1, [steady]), F.port(2, [dropping])])
            run.observe(t + 5, [F.port(1, [steady]), F.port(2)])
        }
        run.observe(50, [F.port(1, [steady]), F.port(2, [dropping])])
        let finding = try #require(run.last.first)
        #expect(run.last.count == 1)
        #expect(finding.deviceID == dropping.id)
        #expect(finding.portKey == F.port2)
        #expect(run.health.history(ofDevice: steady.id)?.cycles == 0)
    }

    @Test func oneMoveBetweenPortsIsNotACycle() {
        var run = HealthRun()
        let onPort2 = F.drive(location: 0x0210_0000)
        run.observe(0, [F.port(1), F.port(2)])
        for i in 0..<3 {
            let t = 20 + Double(i) * 20
            run.observe(t, [F.port(1, [F.drive()]), F.port(2)])
            run.observe(t + 5, [F.port(1), F.port(2)])
            run.observe(t + 10, [F.port(1), F.port(2, [onPort2])])
            run.observe(t + 15, [F.port(1), F.port(2)])
        }
        #expect(run.last.isEmpty)
        run.observe(100, [F.port(1, [F.drive()]), F.port(2)])
        #expect(run.health.history(ofDevice: F.drive().id)?.cycles == 0)
    }

    @Test func moveToASlowerPortIsNotARegression() {
        var run = HealthRun()
        run.observe(0, [F.port(1, [F.drive()]), F.port(2)])
        run.observe(20, [F.port(1, [F.drive()]), F.port(2)])
        run.observe(30, [F.port(1), F.port(2, [F.drive(location: 0x0210_0000, bps: 5_000_000_000)])])
        #expect(run.last.isEmpty)
    }

    @Test func moveToASlowerPortOfTheSameDockIsNotARegression() {
        func hub(_ name: String, location: UInt32, _ children: [DeviceNode]) -> DeviceNode {
            F.usb(name, location: location, kind: .hub, children: children)
        }
        let slow = F.drive(location: 0x0121_0000, bps: 5_000_000_000)
        var run = HealthRun()
        run.observe(0, [F.port(1, [hub("Front hub", location: 0x0110_0000, [F.drive(location: 0x0111_0000)]),
                                   hub("Rear hub", location: 0x0120_0000, [])])])
        run.observe(20, [F.port(1, [hub("Front hub", location: 0x0110_0000, [F.drive(location: 0x0111_0000)]),
                                    hub("Rear hub", location: 0x0120_0000, [])])])
        run.observe(25, [F.port(1, [hub("Front hub", location: 0x0110_0000, []),
                                    hub("Rear hub", location: 0x0120_0000, [])])])
        run.observe(30, [F.port(1, [hub("Front hub", location: 0x0110_0000, []),
                                    hub("Rear hub", location: 0x0120_0000, [slow])])])
        #expect(run.last.isEmpty)
    }

    @Test func dockPartFallingBackToUSB2IsNotAlsoASpeedRegression() {
        func dock(_ part: DeviceNode) -> DeviceNode {
            DeviceNode(id: "tb:d0c", bus: .thunderbolt, kind: .dock, name: "Dock", internalParts: [part])
        }
        var run = HealthRun()
        run.observe(0, [F.port(1, [dock(F.usb("USB hub", location: 0x0110_0000, kind: .hub))])])
        run.observe(20, [F.port(1, [dock(F.usb("USB hub", location: 0x0110_0000, kind: .hub))])])
        // Still declares USB 3.2, so usb2Fallback reports the hub against the dock instead.
        run.observe(30, [F.port(1, [dock(F.usb("USB hub", location: 0x0010_0000, bps: 480_000_000, kind: .hub))])])
        #expect(!run.kinds().contains(.speedRegression))
    }

    @Test func usb2FallbackIsNotAlsoASpeedRegression() {
        var run = HealthRun()
        run.observe(0, [F.port(1, [F.drive()])])
        run.observe(20, [F.port(1, [F.drive()])])
        // Still declares USB 3.2, so usb2Fallback reports it instead.
        run.observe(30, [F.port(1, [F.drive(location: 0x0010_0000, bps: 480_000_000)])])
        #expect(run.last.isEmpty)
    }

    @Test func subjectIDsCarryNoSerial() {
        var run = HealthRun()
        run.observe(0, [F.port(1)])
        run.cycle(F.drive(), on: 1, times: 3, from: 20)
        run.observe(60, [F.port(1, [F.drive(location: 0x0010_0000, bps: 480_000_000, version: "2.1")])])
        #expect(run.kinds().contains(.flakyConnection))
        #expect(run.kinds().contains(.speedRegression))
        for finding in run.last {
            #expect(!finding.id.contains("S6XNNS0W123456"))
            #expect(!finding.detail.contains("S6XNNS0W123456"))
        }
    }
}
