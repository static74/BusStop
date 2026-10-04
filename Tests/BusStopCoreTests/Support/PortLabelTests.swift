import Foundation
import Testing
@testable import BusStopCore

@Suite("Port location catalogue")
struct PortLocationCatalogTests {
    @Test func listsEveryModelSorted() {
        let models = PortLocationCatalog.allModels
        #expect(models.count == 59)
        #expect(models == models.sorted())
        #expect(Set(models).count == models.count)
        #expect(models.contains("MacBookAir10,1"))
        #expect(models.contains("Mac17,9"))
    }

    @Test func looksUpModels() throws {
        let air = try #require(PortLocationCatalog.entry(for: "MacBookAir10,1"))
        #expect(air.marketingName == "MacBook Air (M1, 2020)")
        #expect(air.ports.map(\.location) == ["Left Rear", "Left Front"])
        #expect(air.ports.allSatisfy { $0.isThunderbolt })

        #expect(PortLocationCatalog.entry(for: " Mac16,10\n")?.model == "Mac16,10")
        #expect(PortLocationCatalog.entry(for: "Mac99,1") == nil)
        #expect(PortLocationCatalog.entry(for: "") == nil)
        #expect(PortLocationCatalog.marketingName(for: "Mac16,10") == "Mac mini (2024, M4)")
    }

    @Test func macBookProKeepsTheSourceOrder() throws {
        let pro = try #require(PortLocationCatalog.entry(for: "Mac17,9"))
        let rows = pro.ports.map { "\($0.connector) \($0.portNumber) \($0.location)" }
        #expect(rows == [
            "magsafe 1 Left Rear", "usb-c 1 Left Center", "usb-c 2 Left Front", "sd 1 Right Front",
            "hdmi 1 Right Rear", "usb-c 3 Right Center",
        ])
        #expect(pro.ports(connector: "usb-c").map(\.capability) == Array(repeating: "Thunderbolt 5", count: 3))
        #expect(pro.isCompactDesktop == false)
    }

    @Test func generatedRowsAreWellFormed() {
        let connectors: Set<String> = ["usb-c", "magsafe", "usb-a", "hdmi", "sd", "ethernet", "ac-power"]
        for model in PortLocationCatalog.allModels {
            guard let entry = PortLocationCatalog.entry(for: model) else {
                Issue.record("\(model) is listed but has no entry")
                continue
            }
            #expect(!entry.ports.isEmpty, "\(model) has no ports")
            #expect(!entry.marketingName.isEmpty)
            let keys = entry.ports.map { "\($0.connector)#\($0.portNumber)" }
            #expect(Set(keys).count == keys.count, "\(model) repeats a connector number")
            for row in entry.ports {
                #expect(connectors.contains(row.connector), "\(model) uses connector \(row.connector)")
                #expect(!row.location.isEmpty)
            }
        }
    }

    @Test func recognisesCompactDesktops() {
        #expect(PortLocationCatalog.isCompactDesktop(model: "Mac16,10"))
        #expect(PortLocationCatalog.isCompactDesktop(model: "Mac15,14"))
        #expect(PortLocationCatalog.isCompactDesktop(model: "Macmini9,1"))
        #expect(PortLocationCatalog.isCompactDesktop(model: "Macmini8,1"))
        #expect(!PortLocationCatalog.isCompactDesktop(model: "Mac17,9"))
        #expect(!PortLocationCatalog.isCompactDesktop(model: "Mac16,3"))
        #expect(!PortLocationCatalog.isCompactDesktop(model: "Mac99,1"))
    }
}

@Suite("Port labels")
struct PortLabelTests {
    private func label(_ number: Int, siblings: [Int], model: String, userNames: [String: String] = [:],
                       thunderbolt: Bool? = nil) -> (label: PortLabel, capability: String?) {
        label(.usbC, number, siblings: siblings, model: model, userNames: userNames, thunderbolt: thunderbolt)
    }

    private func label(_ kind: PortKind, _ number: Int, siblings: [Int], model: String,
                       userNames: [String: String] = [:], thunderbolt: Bool? = nil) -> (label: PortLabel, capability: String?) {
        let type: Int
        switch kind {
        case .magSafe: type = PortKey.magSafeType
        case .hdmi: type = PortKey.hdmiType
        default: type = PortKey.usbCType
        }
        return PortLabeler.label(kind: kind, number: number, key: PortKey(type: type, number: number),
                                 siblings: siblings, model: model, userNames: userNames,
                                 supportsThunderbolt: thunderbolt)
    }

    @Test func exactCatalogueMatch() {
        let front = label(2, siblings: [1, 2], model: "MacBookAir10,1")
        #expect(front.label.location == "Left Front")
        #expect(front.label.source == .catalog)
        #expect(front.label.title == "Left Front · USB-C")
        #expect(front.capability == "Thunderbolt / USB 4")

        #expect(label(1, siblings: [1, 2], model: "MacBookAir10,1").label.location == "Left Rear")
    }

    @Test func macBookProPorts() {
        let model = "Mac17,9"
        let magSafe = label(.magSafe, 1, siblings: [1], model: model)
        #expect(magSafe.label.title == "Left Rear · MagSafe")
        #expect(magSafe.capability == "MagSafe 3")

        let right = label(3, siblings: [1, 2, 3], model: model)
        #expect(right.label.title == "Right Center · USB-C")
        #expect(right.capability == "Thunderbolt 5")

        #expect(label(.hdmi, 1, siblings: [1], model: model).label.location == "Right Rear")
        #expect(label(.sdCard, 1, siblings: [1], model: model).label.location == "Right Front")

        // The one MagSafe and HDMI port match whatever number the kernel uses.
        let magSafeTwo = label(.magSafe, 2, siblings: [2], model: model)
        #expect(magSafeTwo.label.location == "Left Rear")
        #expect(magSafeTwo.label.source == .catalogRank)
    }

    @Test func rankFallbackForNonContiguousNumbers() {
        // An M5 MacBook Pro publishes USB-C ports 1, 2 and 4; the catalogue lists 1, 2 and 3.
        let model = "Mac17,2"
        let siblings = [1, 2, 4]
        let first = label(1, siblings: siblings, model: model)
        let second = label(2, siblings: siblings, model: model)
        let fourth = label(4, siblings: siblings, model: model)
        #expect(first.label.location == "Left Center")
        #expect(first.label.source == .catalog)
        #expect(second.label.location == "Left Front")
        #expect(second.label.source == .catalog)
        #expect(fourth.label.location == "Right Center")
        #expect(fourth.label.source == .catalogRank)
        #expect(fourth.label.title == "Right Center · USB-C")
        #expect(fourth.capability == "Thunderbolt 4")
    }

    @Test func rankFallbackStaysOneToOne() {
        // With numbers {2, 3, 4}, matching 2 and 3 exactly would leave 4 on row 3 twice.
        let locations = [2, 3, 4].map { label($0, siblings: [2, 3, 4], model: "Mac17,2").label.location }
        #expect(locations == ["Left Center", "Left Front", "Right Center"])
    }

    @Test func noRankFallbackWhenCountsDiffer() {
        let extra = label(4, siblings: [1, 2, 3, 4], model: "Mac17,2")
        #expect(extra.label.source == .generic)
        #expect(extra.label.title == "USB-C 4")
        #expect(extra.capability == nil)
        // Ports that do match keep their rows.
        #expect(label(3, siblings: [1, 2, 3, 4], model: "Mac17,2").label.location == "Right Center")
    }

    @Test func userOverrideWins() {
        let named = label(1, siblings: [1, 2, 3], model: "Mac17,9", userNames: ["2/1": "Desk dock"])
        #expect(named.label.source == .user)
        #expect(named.label.title == "Desk dock")
        #expect(named.label.shortTitle == "Desk dock")
        #expect(named.capability == "Thunderbolt 5")

        let blank = label(1, siblings: [1, 2, 3], model: "Mac17,9", userNames: ["2/1": "   "])
        #expect(blank.label.source == .catalog)

        let otherPort = label(2, siblings: [1, 2, 3], model: "Mac17,9", userNames: ["2/1": "Desk dock"])
        #expect(otherPort.label.location == "Left Front")

        let unknownModel = label(5, siblings: [5], model: "Mac99,1", userNames: ["2/5": "Hub"])
        #expect(unknownModel.label.title == "Hub")
        #expect(unknownModel.capability == nil)
    }

    @Test func desktopHeuristicWhenNumbersDisagreeWithCapability() {
        // Mac mini M4: suppose the rear Thunderbolt ports are 1-3 and the front ports 5 and 6.
        let model = "Mac16,10"
        let siblings = [1, 2, 3, 5, 6]
        let rear = label(1, siblings: siblings, model: model, thunderbolt: true)
        #expect(rear.label.location == "Rear")
        #expect(rear.label.title == "Rear · USB-C")
        #expect(rear.capability == "Thunderbolt 4")
        let front = label(5, siblings: siblings, model: model, thunderbolt: false)
        #expect(front.label.location == "Front")
        #expect(front.capability == "USB 3 (10 Gb/s)")
    }

    @Test func desktopCatalogueMatchKeptWhenCapabilityAgrees() {
        let model = "Mac16,10"
        let front = label(1, siblings: [1, 2, 3, 4, 5], model: model, thunderbolt: false)
        #expect(front.label.location == "Front (left)")
        #expect(front.label.source == .catalog)
        let rear = label(4, siblings: [1, 2, 3, 4, 5], model: model, thunderbolt: true)
        #expect(rear.label.location == "Rear (center)")
        // Without capability information the catalogue is trusted.
        #expect(label(1, siblings: [1, 2, 3, 4, 5], model: model).label.location == "Front (left)")
    }

    @Test func desktopHeuristicForUnlistedMacMini() {
        #expect(label(3, siblings: [1, 2, 3], model: "Macmini10,1", thunderbolt: true).label.location == "Rear")
        #expect(label(3, siblings: [1, 2, 3], model: "Macmini10,1", thunderbolt: false).label.location == "Front")
        #expect(label(3, siblings: [1, 2, 3], model: "Macmini10,1").label.source == .generic)
    }

    @Test func noHeuristicWhereCapabilityDoesNotTellPlaces() {
        // Mac Studio M1 Ultra has Thunderbolt at the front and the rear.
        let ultra = label(8, siblings: [1, 2, 3, 4, 5, 6, 8], model: "Mac13,2", thunderbolt: true)
        #expect(ultra.label.source == .generic)
        // Laptops never use the desktop heuristic.
        let laptop = label(5, siblings: [1, 2, 3, 5], model: "Mac17,9", thunderbolt: true)
        #expect(laptop.label.source == .generic)
    }

    @Test func genericForUnknownModel() {
        let result = label(2, siblings: [1, 2], model: "Mac99,1")
        #expect(result.label.source == .generic)
        #expect(result.label.location == nil)
        #expect(result.label.title == "USB-C 2")
        #expect(result.capability == nil)
        #expect(label(.hdmi, 1, siblings: [1], model: "Mac99,1").label.title == "HDMI 1")
    }

    @Test func sortKeyFollowsCatalogueOrder() {
        let model = "Mac17,9"
        let ports: [(PortKind, Int)] = [(.usbC, 3), (.usbA, 1), (.hdmi, 1), (.usbC, 7), (.usbC, 2), (.magSafe, 1),
                                        (.usbC, 1)]
        let usbCNumbers = [1, 2, 3, 7]
        let sorted = ports.sorted { lhs, rhs in
            let left = PortLabeler.sortKey(kind: lhs.0, number: lhs.1,
                                           siblings: lhs.0 == .usbC ? usbCNumbers : [lhs.1], model: model)
            let right = PortLabeler.sortKey(kind: rhs.0, number: rhs.1,
                                            siblings: rhs.0 == .usbC ? usbCNumbers : [rhs.1], model: model)
            return left < right
        }
        let names = sorted.map { "\($0.0.catalogConnector) \($0.1)" }
        // Catalogue rows first (MagSafe, USB-C 1, USB-C 2, HDMI, USB-C 3), then the rest by kind and number.
        #expect(names == ["magsafe 1", "usb-c 1", "usb-c 2", "hdmi 1", "usb-c 3", "usb-c 7", "usb-a 1"])

        #expect(PortLabeler.sortKey(kind: .usbC, number: 2, siblings: [1, 2], model: "Mac99,1")
            == (1, PortKind.usbC.sortRank, 2))
        #expect(PortLabeler.sortKey(kind: .magSafe, number: 1, siblings: [1], model: model) == (0, 0, 1))
    }

    @Test func sortKeyDropsRejectedDesktopMatches() {
        let key = PortLabeler.sortKey(kind: .usbC, number: 1, siblings: [1, 2, 3, 5, 6], model: "Mac16,10",
                                      supportsThunderbolt: true)
        #expect(key.0 == 1)
    }

    @Test func areaOfLocation() {
        #expect(PortLabeler.area(of: "Rear (left)") == "Rear")
        #expect(PortLabeler.area(of: "Top/Front (right)") == "Top/Front")
        #expect(PortLabeler.area(of: "Front") == "Front")
        #expect(PortLabeler.area(of: "") == "")
    }
}
