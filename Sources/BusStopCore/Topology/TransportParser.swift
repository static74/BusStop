import Foundation

/// One `IOPortTransportState*` node joined to its port.
struct TopologyTransportRecord {
    let node: RawNode
    let kind: TransportKind
    let portKey: PortKey
    /// Carried inside a Thunderbolt / USB4 tunnel (`Tunneled = Yes`, or a
    /// path such as `"Port-USB-C@1/CIO/USB3@0"`).
    let isTunneled: Bool
    /// The node's own `Active` flag; nil when it does not publish one.
    let activeFlag: Bool?

    var properties: PropertyBag { node.properties }

    /// The decoded link for this transport. CC carries no data link; CIO
    /// links come from the Thunderbolt switch, not from this node.
    var link: LinkInfo? {
        TransportParser.link(kind: kind, properties: properties)
    }

    /// The product the transport's metadata names (USB 2 `Product`,
    /// DisplayPort `ProductName`).
    var productName: String? {
        let p = properties
        let metadata = p.bag("Metadata")
        switch kind {
        case .displayPort:
            return TopologyText.clean(p.string("ProductName") ?? metadata?.string("ProductName"))
        case .usb2, .usb3:
            return TopologyText.clean(p.string("Product") ?? metadata?.string("Product"))
        default:
            return TopologyText.clean(p.string("ProductName") ?? p.string("Product"))
        }
    }
}

/// Reads transport states, cable e-markers and liquid detection for each port.
enum TransportParser {
    /// True for `IOPortTransportState*` nodes and anything else that
    /// describes itself with `TransportTypeDescription`.
    static func isTransportNode(_ node: RawNode) -> Bool {
        node.className.hasPrefix("IOPortTransportState") || node.properties.has("TransportTypeDescription")
    }

    /// The transport kind from `TransportTypeDescription`, else from the
    /// class name suffix (`IOPortTransportStateUSB3` → USB3).
    static func kind(of node: RawNode) -> TransportKind? {
        if let description = node.properties.string("TransportTypeDescription"),
           let kind = TransportKind(ioKitName: description) {
            return kind
        }
        let prefix = "IOPortTransportState"
        if node.className.hasPrefix(prefix) {
            return TransportKind(ioKitName: String(node.className.dropFirst(prefix.count)))
        }
        return nil
    }

    /// The decoded link for a transport kind. CC and CIO return nil here.
    static func link(kind: TransportKind, properties: PropertyBag?) -> LinkInfo? {
        switch kind {
        case .usb2: return LinkDecoding.usb2TransportLink(properties)
        case .usb3: return LinkDecoding.usb3TransportLink(properties)
        case .displayPort: return LinkDecoding.displayPortLink(properties)
        case .hdmi: return LinkInfo(family: .hdmi, generation: "HDMI")
        case .cc, .cio: return nil
        }
    }

    /// Every transport node joined to a captured port, sorted by port key,
    /// kind and registry ID.
    static func parse(_ index: TopologyNodeIndex, ports: TopologyPortTable) -> [TopologyTransportRecord] {
        var records: [TopologyTransportRecord] = []
        for node in index.nodes where isTransportNode(node) && !PortParser.isPortNode(node) {
            guard let kind = kind(of: node), let portKey = ports.owner(of: node, index: index) else { continue }
            records.append(TopologyTransportRecord(node: node, kind: kind, portKey: portKey,
                                                   isTunneled: isTunneled(node, index: index),
                                                   activeFlag: node.properties.bool("Active")))
        }
        return records.sorted { lhs, rhs in
            if lhs.portKey != rhs.portKey { return lhs.portKey < rhs.portKey }
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.node.id < rhs.node.id
        }
    }

    /// A transport is tunnelled when it says so, when its description path
    /// runs through CIO, or when a captured ancestor is a CIO transport.
    static func isTunneled(_ node: RawNode, index: TopologyNodeIndex) -> Bool {
        let p = node.properties
        if p.bool("Tunneled") == true { return true }
        for key in ["TransportDescription", "Description"] {
            if let path = p.string(key), path.uppercased().contains("/CIO/") { return true }
        }
        return index.ancestors(of: node).contains { ancestor in
            isTransportNode(ancestor) && kind(of: ancestor) == .cio
        }
    }

    /// The port's active, non-tunnelled transports, fastest kind first, CC
    /// omitted.
    ///
    /// When the port publishes `TransportsActive`, that list decides which
    /// kinds are live; a transport node that explicitly says `Active = No`
    /// removes its kind. A listed kind without a node still counts. Without
    /// the list, a node's own `Active = Yes` decides.
    static func activeTransports(for record: TopologyPortRecord,
                                 transports: [TopologyTransportRecord]) -> [TransportInfo] {
        let own = transports.filter { $0.portKey == record.key && !$0.isTunneled && $0.kind != .cc }
        let listed = record.listedActiveTransports
        var kinds = Set(own.map(\.kind))
        if let listed { kinds.formUnion(listed) }

        var result: [TransportInfo] = []
        for kind in kinds.sorted() {
            let nodes = own.filter { $0.kind == kind }
            let isActive: Bool
            if let listed {
                isActive = listed.contains(kind) && (nodes.isEmpty || nodes.contains { $0.activeFlag != false })
            } else {
                isActive = nodes.contains { $0.activeFlag == true }
            }
            guard isActive else { continue }
            let candidates = nodes.filter { $0.activeFlag != false }
            let best = candidates.max { lhs, rhs in
                let l = lhs.link?.bitsPerSecond ?? -1
                let r = rhs.link?.bitsPerSecond ?? -1
                if l != r { return l < r }
                if (lhs.activeFlag == true) != (rhs.activeFlag == true) { return rhs.activeFlag == true }
                return lhs.node.id > rhs.node.id
            }
            let link = best?.link ?? link(kind: kind, properties: nil)
            result.append(TransportInfo(kind: kind, isActive: true, isTunneled: false, link: link,
                                        productName: best?.productName))
        }
        return result
    }

    /// The port's tunnelled transports that are live (a dock's USB 3 or
    /// DisplayPort inside CIO). Evidence for docks and displays only; they
    /// never appear in `activeTransports`.
    static func tunneledTransports(for key: PortKey, transports: [TopologyTransportRecord]) -> [TopologyTransportRecord] {
        transports.filter { $0.portKey == key && $0.isTunneled && $0.activeFlag != false }
    }

    // MARK: - Cable

    /// Cable details from the port's `ActiveCable` / `OpticalCable` flags and
    /// the cable e-marker (`IOPortTransportComponentCCUSBPDSOPp`, SOP').
    ///
    /// Nil when nothing is plugged in (the e-marker keys go stale after an
    /// unplug) or when there is no e-marker and neither flag is set.
    static func cable(for record: TopologyPortRecord, index: TopologyNodeIndex,
                      ports: TopologyPortTable) -> CableInfo? {
        guard record.connectionActive else { return nil }
        let p = record.properties
        let activeFlag = p.bool("ActiveCable")
        let opticalFlag = p.bool("OpticalCable")

        let marker = index.nodes
            .filter { isCableMarker($0) && ports.owner(of: $0, index: index) == record.key }
            .min { lhs, rhs in
                // Prefer the near end (SOP') over the far end (SOP'').
                let l = lhs.className.hasSuffix("SOPpp") ? 1 : 0
                let r = rhs.className.hasSuffix("SOPpp") ? 1 : 0
                return l != r ? l < r : lhs.id < rhs.id
            }

        guard marker != nil || activeFlag == true || opticalFlag == true else { return nil }

        var info = CableInfo(isActive: activeFlag, isOptical: opticalFlag)
        guard let marker else { return info }
        let mp = marker.properties
        let metadata = mp.bag("Metadata")
        info.typeDescription = TopologyText.clean(metadata?.string("Product Type Description")
            ?? mp.string("Product Type Description"))
        info.pdRevision = mp.int("Specification Revision") ?? metadata?.int("Specification Revision")

        let vdos = (metadata?.array("VDOs") ?? metadata?.array("VDOs (SOP1)") ?? mp.array("VDOs") ?? [])
            .map(vdoValue)
        if let decoded = decodeCableVDOs(vdos) {
            info.vendorID = decoded.vendorID
            info.productID = decoded.productID
            info.speedDescription = decoded.speedDescription
            info.currentRatingMilliamps = decoded.currentMilliamps
            if info.typeDescription == nil { info.typeDescription = decoded.typeDescription }
            if info.isActive == nil, let active = decoded.isActive { info.isActive = active }
        }
        if info.isActive == nil, let type = info.typeDescription?.lowercased() {
            if type.contains("active") { info.isActive = true } else if type.contains("passive") { info.isActive = false }
        }
        return info
    }

    /// True for SOP' and SOP'' component nodes (the cable's e-marker).
    static func isCableMarker(_ node: RawNode) -> Bool {
        if node.className.hasPrefix("IOPortTransportComponentCCUSBPDSOPp") { return true }
        let name = node.properties.string(["ComponentName", "AddressDescription", "Address Description"])
        return name == "SOP'" || name == "SOP''"
    }

    /// A VDO as a 32-bit value: 4-byte little-endian `Data` or a number.
    static func vdoValue(_ value: PlistValue) -> UInt32? {
        switch value {
        case .data(let d):
            guard d.count >= 4 else { return nil }
            let bytes = [UInt8](d.prefix(4))
            return UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        default:
            guard let i = value.int64Value, i >= 0, i <= Int64(UInt32.max) else { return nil }
            return UInt32(i)
        }
    }

    /// Decoded fields of a cable's Discover Identity response (USB PD 3.x:
    /// VDO 0 ID header, VDO 2 product, VDO 3 cable). Nil unless the ID header
    /// says the responder is a cable.
    struct CableVDOs {
        var vendorID: Int?
        var productID: Int?
        var isActive: Bool?
        var typeDescription: String?
        var speedDescription: String?
        var currentMilliamps: Int?
    }

    static func decodeCableVDOs(_ vdos: [UInt32?]) -> CableVDOs? {
        guard let header = vdos.first ?? nil else { return nil }
        let productType = (header >> 27) & 0b111
        guard productType == 3 || productType == 4 else { return nil }
        var result = CableVDOs()
        result.isActive = productType == 4
        result.typeDescription = productType == 4 ? "Active Cable" : "Passive Cable"
        let vendor = Int(header & 0xFFFF)
        result.vendorID = vendor == 0 ? nil : vendor
        if vdos.count > 2, let product = vdos[2] {
            let pid = Int(product >> 16)
            result.productID = pid == 0 ? nil : pid
        }
        if vdos.count > 3, let cable = vdos[3] {
            switch cable & 0b111 {
            case 0: result.speedDescription = "USB 2.0 (480 Mb/s)"
            case 1: result.speedDescription = "USB 3.2 Gen 1 (5 Gb/s)"
            case 2: result.speedDescription = "USB 3.2 Gen 2 (10 Gb/s)"
            case 3: result.speedDescription = "USB4 Gen 3 (40 Gb/s)"
            case 4: result.speedDescription = "USB4 Gen 4 (80 Gb/s)"
            default: break
            }
            switch (cable >> 5) & 0b11 {
            case 1: result.currentMilliamps = 3000
            case 2: result.currentMilliamps = 5000
            default: break
            }
        }
        return result
    }

    // MARK: - Liquid detection

    /// `LDCM_LiquidDetected` on the port, or `LiquidDetected` on one of its
    /// `AppleHPMLDCM*` feature nodes.
    static func liquidDetected(for record: TopologyPortRecord, index: TopologyNodeIndex,
                               ports: TopologyPortTable) -> Bool {
        if record.properties.bool("LDCM_LiquidDetected") == true { return true }
        return index.nodes.contains { node in
            let isLDCM = node.className.hasPrefix("AppleHPMLDCM")
                || node.properties.string("FeatureTypeDescription") == "LDCM"
            return isLDCM && node.properties.bool("LiquidDetected") == true
                && ports.owner(of: node, index: index) == record.key
        }
    }
}
