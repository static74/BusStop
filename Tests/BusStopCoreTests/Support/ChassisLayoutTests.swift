import Foundation
import Testing
@testable import BusStopCore

@Suite("Chassis layout")
struct ChassisLayoutTests {
    typealias S = DemoTestSupport
    typealias T = TopologyFixtures

    private func entries() -> [MachineCatalogEntry] {
        PortLocationCatalog.allModels.compactMap(PortLocationCatalog.entry(for:))
    }

    private func machine(_ entry: MachineCatalogEntry) -> MachineSummary {
        MachineSummary(model: entry.model, name: entry.marketingName, osVersion: "27.0", isLaptop: false)
    }

    private func layout(_ snapshot: HostSnapshot) -> ChassisLayout {
        ChassisLayout.resolve(machine: snapshot.machine, ports: snapshot.ports)
    }

    /// "usb-c 2 Left Front" for a live slot, "sd Right Front" for a passive one.
    private func names(_ layout: ChassisLayout, in snapshot: HostSnapshot) -> [String] {
        layout.slots.map { slot in
            guard let key = slot.portKey, let port = snapshot.port(key) else { return "\(slot.connector) \(slot.location)" }
            return "\(slot.connector) \(port.number) \(slot.location)"
        }
    }

    @Test func parsesEachForm() throws {
        #expect(try #require(ChassisLayout.parse("Left Rear")) == (.left, 0))
        #expect(try #require(ChassisLayout.parse("Right Front")) == (.right, 2))
        #expect(try #require(ChassisLayout.parse("Rear (left-center)")) == (.rear, 2))
        #expect(try #require(ChassisLayout.parse("Top/Front (right)")) == (.front, 5))
        #expect(try #require(ChassisLayout.parse("Rear I/O card (left)")) == (.rear, 1))
        #expect(try #require(ChassisLayout.parse("Rear")) == (.rear, 3))
        #expect(ChassisLayout.parse("Desk dock") == nil)
        #expect(ChassisLayout.parse("Rear (behind)") == nil)
        #expect(ChassisLayout.parse("") == nil)
    }

    @Test func everyCatalogueLocationParses() {
        for entry in entries() {
            for row in entry.ports {
                #expect(ChassisLayout.parse(row.location) != nil, "\(entry.model) \(row.location)")
            }
        }
    }

    /// The layout finds a port's row by connector and location, so no row
    /// index is stored on the port.
    @Test func connectorAndLocationAreUniquePerModel() {
        for entry in entries() {
            let keys = entry.ports.map { "\($0.connector) \($0.location)" }
            #expect(Set(keys).count == keys.count, "\(entry.model)")
        }
    }

    @Test func everyCataloguedModelHasANamedFamily() {
        for entry in entries() {
            let family = ChassisFamily(machine: machine(entry))
            #expect(family != .other, "\(entry.model)")
            #expect((family == .laptop) == entry.marketingName.hasPrefix("MacBook"), "\(entry.model)")
        }
    }

    @Test func noTwoSlotsShareAPlace() {
        for entry in entries() {
            let ports = entry.ports.enumerated().compactMap { index, row -> PhysicalPort? in
                guard let kind = PortKind.allCases.first(where: { $0.catalogConnector == row.connector }) else {
                    return nil
                }
                return PhysicalPort(key: PortKey(type: 100 + index, number: row.portNumber), kind: kind,
                                    number: row.portNumber, registryName: "",
                                    label: PortLabel(location: nil, source: .generic, connector: "", number: 0),
                                    catalogLocation: row.location)
            }
            let layout = ChassisLayout.resolve(machine: machine(entry), ports: ports)
            let places = layout.slots.map { "\($0.face) \($0.position)" }
            #expect(layout.unplaced.isEmpty, "\(entry.model)")
            #expect(layout.slots.count == entry.ports.count, "\(entry.model)")
            #expect(Set(places).count == places.count, "\(entry.model)")
            #expect(layout.slots.allSatisfy { $0.position > 0 && $0.position < 1 })
        }
    }

    @Test func renamedPortKeepsItsPlace() {
        let raw = DemoScenario.studioDesk.raw(at: S.date)
        let named = TopologyBuilder.build(raw, options: BuildOptions(userPortNames: ["2/1": "Desk dock",
                                                                                     "17/1": "Charger"],
                                                                     isDemo: true))
        #expect(named.port(PortKey(type: 2, number: 1))?.label.location == "Desk dock")
        #expect(layout(named) == layout(S.snapshot(.studioDesk)))
    }

    @Test func rankMatchedM5Numbering() {
        // Mac17,2 publishes USB-C ports 1, 2 and 4; the catalogue lists 1, 2 and 3.
        let snapshot = S.snapshot(.unplugged)
        let layout = layout(snapshot)
        #expect(names(layout, in: snapshot) == [
            "magsafe 1 Left Rear", "usb-c 1 Left Center", "usb-c 2 Left Front",
            "hdmi 1 Right Rear", "usb-c 4 Right Center", "sd 1 Right Front",
        ])
        #expect(layout.slots.allSatisfy { $0.portKey != nil })
        #expect(layout.slots.map(\.face) == [.left, .left, .left, .right, .right, .right])
        #expect(layout.slots.prefix(3).map(\.position) == [0.25, 0.5, 0.75])
    }

    @Test func desktopAreaOnlyFallback() {
        // Mac mini M4 numbered rear Thunderbolt 1-3 and front USB 5 and 6: the labeler places them by area.
        let thunderbolt = ["CC", "USB2", "USB3", "DisplayPort", "CIO"]
        let ports = [1, 2, 3].map { T.port(id: UInt64($0), number: $0, supported: thunderbolt) }
            + [5, 6].map { T.port(id: UInt64($0), number: $0, supported: ["USB2", "USB3"]) }
            + [T.port(id: 9, type: 6, number: 1, description: "HDMI", supported: [],
                      className: "AppleHDMIPortController")]
        let snapshot = TopologyBuilder.build(T.raw(model: "Mac16,10", hasBattery: false, ports: ports))
        let layout = layout(snapshot)
        #expect(layout.family == .macMini)
        #expect(layout.unplaced.isEmpty)
        #expect(names(layout, in: snapshot) == [
            "usb-c 5 Front", "usb-c 6 Front", "usb-c 1 Rear", "usb-c 2 Rear", "usb-c 3 Rear", "hdmi 1 Rear",
        ])
        #expect(layout.slots.allSatisfy { $0.portKey != nil })
    }

    @Test func unlistedMacMiniPlacesByArea() {
        let ports = [T.port(id: 1, number: 1), T.port(id: 2, number: 2, supported: ["USB2", "USB3"])]
        let snapshot = TopologyBuilder.build(T.raw(model: "Macmini10,1", hasBattery: false, ports: ports))
        let layout = layout(snapshot)
        #expect(layout.family == .macMini)
        #expect(names(layout, in: snapshot) == ["usb-c 2 Front", "usb-c 1 Rear"])
        #expect(layout.unplaced.isEmpty)
    }

    @Test func unknownModelWithAndWithoutBattery() {
        let ports = [T.port(id: 1, number: 1), T.port(id: 2, number: 2)]
        let laptop = layout(TopologyBuilder.build(T.raw(model: "Mac99,1", hasBattery: true, ports: ports)))
        let desktop = layout(TopologyBuilder.build(T.raw(model: "Mac99,1", hasBattery: false, ports: ports)))
        #expect(laptop.family == .laptop)
        #expect(desktop.family == .other)
        for result in [laptop, desktop] {
            #expect(result.slots.isEmpty)
            #expect(result.unplaced == [PortKey(type: 2, number: 1), PortKey(type: 2, number: 2)])
        }
    }

    @Test func passiveSlotsForUnreportedConnectors() {
        // Mac mini M2 Pro: the power inlet and Ethernet have no port controller.
        let ports = [1, 2, 3, 4].map { T.port(id: UInt64($0), number: $0) }
            + [1, 2].map { T.port(id: UInt64(10 + $0), type: nil, number: $0, description: "USB-A", supported: [],
                                  className: "IOPort") }
            + [T.port(id: 9, type: 6, number: 1, description: "HDMI", supported: [],
                      className: "AppleHDMIPortController")]
        let snapshot = TopologyBuilder.build(T.raw(model: "Mac14,12", hasBattery: false, ports: ports))
        let layout = layout(snapshot)
        #expect(layout.slots.filter { $0.portKey == nil }.map(\.connector) == ["ac-power", "ethernet"])
        #expect(names(layout, in: snapshot) == [
            "ac-power Rear", "usb-c 1 Rear (leftmost)", "usb-c 2 Rear (left-center)", "usb-c 3 Rear (right-center)",
            "usb-c 4 Rear (rightmost)", "usb-a 1 Rear (left)", "usb-a 2 Rear (right)", "hdmi 1 Rear", "ethernet Rear",
        ])
    }

    @Test(arguments: DemoScenario.allCases)
    func demoScenariosPlaceEveryPort(_ scenario: DemoScenario) {
        let snapshot = S.snapshot(scenario)
        let layout = layout(snapshot)
        #expect(layout.unplaced.isEmpty)
        #expect(snapshot.ports.allSatisfy { $0.catalogLocation != nil })
        #expect(Set(layout.slots.compactMap(\.portKey)) == Set(snapshot.ports.map(\.key)))
        let families: [DemoScenario: ChassisFamily] = [.studioDesk: .laptop, .travel: .laptop,
                                                       .dockStation: .macMini, .unplugged: .laptop,
                                                       .flakyCable: .laptop]
        #expect(layout.family == families[scenario])
    }

    @Test func worstSeverityOnPort() throws {
        var snapshot = S.snapshot(.studioDesk)
        let port = try #require(snapshot.ports.first { !$0.devices.isEmpty })
        let other = try #require(snapshot.ports.first { $0.key != port.key })
        let device = try #require(port.allDevices.last?.device)
        func finding(_ id: String, _ severity: DiagnosticSeverity, port: PortKey? = nil,
                     device: String? = nil) -> Diagnostic {
            Diagnostic(id: id, kind: .usb2Fallback, severity: severity, title: id, detail: "", portKey: port,
                       deviceID: device)
        }

        snapshot.diagnostics = [finding("device", .warning, device: device.id)]
        #expect(snapshot.worstSeverity(on: port.key) == .warning)
        #expect(snapshot.worstSeverity(on: other.key) == nil)

        snapshot.diagnostics.append(finding("liquid", .critical, port: port.key))
        snapshot.diagnostics.append(finding("elsewhere", .info, port: other.key))
        #expect(snapshot.worstSeverity(on: port.key) == .critical)
        #expect(snapshot.worstSeverity(on: other.key) == .info)
    }
}
