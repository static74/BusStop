import Foundation

/// A trained Thunderbolt / USB4 link on a lane adapter.
struct DemoThunderboltLink {
    /// `Current Link Speed`: 0x8 = 10, 0x4 = 20, 0x2 = 40 Gb/s per lane.
    var speedCode: Int
    /// `Current Link Width`: 0x1 one lane, 0x2 two lanes.
    var widthCode: Int
    /// `Supported Link Speed` mask (14 = up to 40 Gb/s per lane).
    var supportedMask: Int = 0xE

    /// `Link Bandwidth`, in units of 100 Mb/s.
    var bandwidth: Int {
        let perLane = LinkDecoding.thunderboltPerLaneGbps(speedCode: speedCode) ?? 0
        let lanes = LinkDecoding.thunderboltWidth(code: widthCode)?.lanes ?? 0
        return perLane * lanes * 10
    }

    /// Two lanes at 40 Gb/s: USB4 v2 / Thunderbolt 5.
    static let tb5 = DemoThunderboltLink(speedCode: 0x2, widthCode: 0x2)
}

/// A protocol adapter on a switch (`"DP or HDMI Adapter"`, `"PCIe Adapter"`, …).
struct DemoThunderboltAdapter {
    var portNumber: Int
    var description: String
    /// A tunnel runs through it (non-empty `Hop Table`).
    var isLive: Bool
}

/// A switch as later builders need it.
struct DemoSwitchRef {
    let id: UInt64
    let className: String
    /// Lane adapters by `Port Number`.
    let lanes: [Int: UInt64]
    let ancestry: [RawAncestor]
}

extension DemoRegistry {
    /// The Mac's own switch for one USB-C port, under `acioN`. Its two lane
    /// adapters carry `Socket ID` = the port number. `type` is the
    /// controller generation (7 on M4 Pro, M4 Max and M5, whose idle lanes
    /// read speed 0 and width 0; 5 on earlier chips, whose idle lanes read
    /// 10 Gb/s on one lane, passed as `idleLink`).
    @discardableResult
    mutating func hostSwitch(acio: Int, socket: Int, uid: Int64, modelName: String, type: Int = 7,
                             link: DemoThunderboltLink?, idleLink: DemoThunderboltLink? = nil,
                             adapters: [DemoThunderboltAdapter] = []) -> DemoSwitchRef {
        let className = "IOThunderboltSwitchType\(type)"
        let ancestry = [
            RawAncestor(id: newID(), className: "IOThunderboltControllerType\(type)",
                        name: "IOThunderboltControllerType\(type)"),
            RawAncestor(id: newID(), className: "AppleThunderboltNHIType\(type)", name: "AppleThunderboltNHIType\(type)"),
            RawAncestor(id: newID(), className: "AppleThunderboltHALType\(type)", name: "AppleThunderboltHALType\(type)"),
            RawAncestor(id: newID(), className: "AppleARMIODevice", name: "acio\(acio)",
                        location: Self.hexLocation(0x0A00_0000 + UInt64(acio) * 0x0400_0000)),
        ]
        let id = newID()
        var ports: [RawNode] = []
        var lanes: [Int: UInt64] = [:]
        for lane in [1, 2] {
            let laneID = newID()
            lanes[lane] = laneID
            var p = Self.laneKeys(portNumber: lane, link: link ?? idleLink)
            if link == nil, idleLink != nil { p["Hop Table"] = .array([]) }
            p["Socket ID"] = .string(String(socket))
            ports.append(RawNode(id: laneID, parentID: id, className: "IOThunderboltPort",
                                 classChain: DemoClassChain.thunderboltPort, name: "IOThunderboltPort",
                                 location: String(lane), properties: PropertyBag(p)))
        }
        let standard = [DemoThunderboltAdapter(portNumber: 0, description: "Thunderbolt Native Host Interface Adapter",
                                               isLive: true)]
        ports += (standard + adapters).map { adapter in adapterNode(adapter, switchID: id) }
        let properties: [String: PlistValue] = [
            "Depth": 0,
            "Route String": 0,
            "UID": .int(uid),
            "Vendor ID": 1452,
            "Device Vendor Name": "Apple Inc.",
            "Device Model Name": .string(modelName),
            "Thunderbolt Version": .int(type >= 7 ? 64 : 32),
            "Upstream Port Number": 0,
            "Max Port Number": 15,
            "Supported Link Speed": .int(Int64((link ?? idleLink)?.supportedMask ?? 0xE)),
        ]
        switches.append(RawThunderboltSwitch(
            node: RawNode(id: id, className: className, classChain: DemoClassChain.thunderboltSwitch(className),
                          name: className, location: "0", properties: PropertyBag(properties)),
            ports: ports, ancestry: ancestry))
        return DemoSwitchRef(id: id, className: className, lanes: lanes, ancestry: ancestry)
    }

    /// A device's switch, `depth` hops from the Mac, cabled to `parentLane`
    /// of `parent`. Its upstream lanes are ports 1 and 2.
    @discardableResult
    mutating func deviceSwitch(below parent: DemoSwitchRef, parentLane: Int, depth: Int, uid: Int64,
                               className: String, vendorID: Int, vendorName: String, deviceID: Int, modelName: String,
                               link: DemoThunderboltLink, downstreamLanes: [Int] = [],
                               adapters: [DemoThunderboltAdapter]) -> DemoSwitchRef {
        let id = newID()
        let laneAncestor = RawAncestor(id: parent.lanes[parentLane] ?? 0, className: "IOThunderboltPort",
                                       name: "IOThunderboltPort", location: String(parentLane))
        let ancestry = [laneAncestor, RawAncestor(id: parent.id, className: parent.className, name: parent.className)]
            + parent.ancestry
        var ports: [RawNode] = []
        var lanes: [Int: UInt64] = [:]
        for lane in [1, 2] + downstreamLanes {
            let laneID = newID()
            lanes[lane] = laneID
            let upstream = lane <= 2
            ports.append(RawNode(id: laneID, parentID: id, className: "IOThunderboltPort",
                                 classChain: DemoClassChain.thunderboltPort, name: "IOThunderboltPort",
                                 location: String(lane),
                                 properties: PropertyBag(Self.laneKeys(portNumber: lane, link: upstream ? link : nil))))
        }
        ports += adapters.map { adapterNode($0, switchID: id) }
        let properties: [String: PlistValue] = [
            "Depth": .int(Int64(depth)),
            "Route String": .int(Int64(parentLane)),
            "UID": .int(uid),
            "Vendor ID": .int(Int64(vendorID)),
            "Device ID": .int(Int64(deviceID)),
            "Device Vendor Name": .string(vendorName),
            "Device Model Name": .string(modelName),
            "Upstream Port Number": 1,
            "Max Port Number": .int(Int64(max(16, (adapters.map(\.portNumber) + downstreamLanes).max() ?? 0))),
            "Thunderbolt Version": 64,
            "Supported Link Speed": .int(Int64(link.supportedMask)),
            "Link Bandwidth": .int(Int64(link.bandwidth)),
        ]
        switches.append(RawThunderboltSwitch(
            node: RawNode(id: id, className: className, classChain: DemoClassChain.thunderboltSwitch(className),
                          name: className, location: String(parentLane), properties: PropertyBag(properties)),
            parentSwitchID: parent.id, ports: ports, ancestry: ancestry))
        return DemoSwitchRef(id: id, className: className, lanes: lanes, ancestry: ancestry)
    }

    /// Keys of a lane adapter (`Description` "Thunderbolt Port").
    private static func laneKeys(portNumber: Int, link: DemoThunderboltLink?) -> [String: PlistValue] {
        [
            "Description": "Thunderbolt Port",
            "Port Number": .int(Int64(portNumber)),
            "Adapter Type": 1,
            "Lane": .int(Int64((portNumber - 1) % 2)),
            "Dual-Link Port": .int(Int64(portNumber % 2 == 1 ? portNumber + 1 : portNumber - 1)),
            "Current Link Speed": .int(Int64(link?.speedCode ?? 0)),
            "Current Link Width": .int(Int64(link?.widthCode ?? 0)),
            "Target Link Width": .int(link == nil ? 0 : 3),
            "Supported Link Speed": .int(Int64(link?.supportedMask ?? 0xE)),
            "Link Bandwidth": .int(Int64(link?.bandwidth ?? 0)),
            "CLx State": 0,
        ]
    }

    private mutating func adapterNode(_ adapter: DemoThunderboltAdapter, switchID: UInt64) -> RawNode {
        let hops: PlistValue = adapter.isLive
            ? .array([.dict(["In HopID": 8, "Out HopID": 8, "Out Port": 1])])
            : .array([])
        let typeCodes = ["PCIe Adapter": 0x100101, "USB Gen T Adapter": 0x200101, "DP or HDMI Adapter": 0x0E0101,
                         "Thunderbolt Native Host Interface Adapter": 2]
        return RawNode(id: newID(), parentID: switchID, className: "IOThunderboltPort",
                       classChain: DemoClassChain.thunderboltPort, name: "IOThunderboltPort",
                       location: String(adapter.portNumber),
                       properties: [
                           "Description": .string(adapter.description),
                           "Port Number": .int(Int64(adapter.portNumber)),
                           "Adapter Type": .int(Int64(typeCodes[adapter.description] ?? 0)),
                           "Hop Table": hops,
                       ])
    }
}
