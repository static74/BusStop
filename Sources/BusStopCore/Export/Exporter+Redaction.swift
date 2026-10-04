import Foundation

/// Redaction for exports.
///
/// What is removed:
/// - every `serialNumber` of devices, chargers and displays (display serials
///   are numbers, so they become nil; the others become "REDACTED");
/// - in every property bag, at any depth, values whose key contains "serial"
///   (any case) or is "ConnectionUUID";
/// - the serial number fields inside EDID blobs, in the base block and in
///   DisplayID extension blocks (product serial, tiled-display serial and
///   the ContainerID);
/// - the computer name of a raw capture;
/// - serial numbers that appear as parts of device, display and diagnostic ids
///   (display ids can end in the panel's serial number).
///
/// What is replaced with a stand-in that is stable within one export, so the
/// export still joins up (and a redacted raw capture still builds the same
/// topology):
/// - Thunderbolt switch UIDs (the `UID` property, and the hex in `tb:` device,
///   display and diagnostic ids). The stand-in keeps the top 16 bits, the
///   vendor, and numbers the units 1, 2, 3 in order of first sight;
/// - UUIDs and USB container IDs (property keys ending in "UUID",
///   `kUSBContainerID`, `ContainerID`), the HPM controller UUIDs of a raw
///   capture and the SMC channel UUIDs (`DxUI`). The stand-in keeps the
///   value's layout and replaces its hex digits with a running number, the
///   same for the dashed and undashed forms of one UUID.
extension Exporter {
    /// A copy of the snapshot with identifying values removed.
    public static func redacted(_ snapshot: HostSnapshot) -> HostSnapshot {
        let redactor = Redactor(serials: serialStrings(in: snapshot))
        var copy = snapshot
        copy.ports = snapshot.ports.map { port in
            var port = port
            port.devices = port.devices.map(redactor.device)
            port.charger = port.charger.map(redacted(_:))
            port.properties = port.properties.map(redactor.bag)
            return port
        }
        copy.otherDevices = snapshot.otherDevices.map(redactor.device)
        copy.power.charger = snapshot.power.charger.map(redacted(_:))
        copy.displays = snapshot.displays.map { display in
            var display = display
            display.serialNumber = nil
            display.id = redactor.id(display.id)
            display.representingDeviceID = display.representingDeviceID.map(redactor.id)
            return display
        }
        copy.diagnostics = snapshot.diagnostics.map { diagnostic in
            var diagnostic = diagnostic
            diagnostic.id = redactor.id(diagnostic.id)
            diagnostic.deviceID = diagnostic.deviceID.map(redactor.id)
            return diagnostic
        }
        return copy
    }

    /// A copy of the raw capture with serials redacted and unit identifiers
    /// replaced in every property bag, display serials removed, controller
    /// and SMC UUIDs replaced, and no computer name.
    public static func redacted(_ raw: RawSnapshot) -> RawSnapshot {
        let redactor = Redactor(serials: [])
        var copy = raw
        copy.machine.computerName = nil
        copy.portNodes = raw.portNodes.map(redactor.node)
        // Sorted by port key, so stand-ins are numbered the same on every run.
        copy.portControllerUUIDs = [:]
        for key in raw.portControllerUUIDs.keys.sorted() {
            copy.portControllerUUIDs[key] = raw.portControllerUUIDs[key].map { redactor.uuid($0) }
        }
        copy.usbDevices = raw.usbDevices.map { device in
            var device = device
            device.node = redactor.node(device.node)
            return device
        }
        copy.thunderboltSwitches = raw.thunderboltSwitches.map { sw in
            var sw = sw
            sw.node = redactor.node(sw.node)
            sw.ports = sw.ports.map(redactor.node)
            return sw
        }
        copy.battery = raw.battery.map(redactor.bag)
        copy.adapter = raw.adapter.map(redactor.bag)
        copy.smcChannels = raw.smcChannels.map { channel in
            var channel = channel
            channel.uuid = channel.uuid.map { redactor.uuid($0) }
            return channel
        }
        copy.displays = raw.displays.map { display in
            var display = display
            display.serialNumber = nil
            return display
        }
        return copy
    }

    /// A copy of the bag with sensitive values replaced, at every depth.
    public static func redacted(_ bag: PropertyBag) -> PropertyBag {
        Redactor(serials: []).bag(bag)
    }

    /// The event with serial numbers and per-unit hardware identifiers removed
    /// from its id, device id, subject id, title and detail, for
    /// `busstop --watch --json` and other exports of individual events.
    ///
    /// An event carries no snapshot, so identifiers are found by the shape of
    /// its ids: the serial number at the end of a `display:` id and the UID
    /// in a `tb:` id become "REDACTED", and the same values are removed from
    /// the title and detail wherever they appear as a whole word.
    public static func redacted(_ event: ConnectionEvent) -> ConnectionEvent {
        var found = Set<String>()
        func scrub(_ id: String) -> String {
            IDShape.scrub(id, found: &found, display: { _ in redactedText }, uid: { _, _ in redactedText })
        }
        var copy = event
        copy.id = scrub(event.id)
        copy.deviceID = event.deviceID.map(scrub)
        copy.subjectID = event.subjectID.map(scrub)
        let words = found.filter { $0.count >= 4 }
        copy.title = IDShape.removing(words, from: event.title)
        copy.detail = IDShape.removing(words, from: event.detail)
        return copy
    }

    /// True for property keys whose values identify a specific unit and are
    /// replaced with "REDACTED": any key containing "serial" (any case) and
    /// "ConnectionUUID". Unit identifiers that other data refers to (UIDs,
    /// UUIDs, container IDs) get a stand-in instead; see `isUnitIdentifierKey`.
    public static func isSensitiveKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower.contains("serial") || lower == "connectionuuid"
    }

    /// True for property keys whose values are per-unit identifiers that get
    /// a stand-in: "UID" (a Thunderbolt switch), any key ending in "UUID",
    /// "kUSBContainerID" and "ContainerID".
    static func isUnitIdentifierKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower == "uid" || lower.hasSuffix("uuid") || lower == "kusbcontainerid" || lower == "containerid"
    }

    // MARK: Private

    private static func redacted(_ charger: ChargerInfo) -> ChargerInfo {
        var charger = charger
        if charger.serialNumber != nil { charger.serialNumber = redactedText }
        return charger
    }

    /// An EDID with its serial fields blanked: bytes 12–15 (the numeric
    /// serial) and the text of any "display serial number" descriptor (tag
    /// 0xFF) in the base block, and in each DisplayID extension block the
    /// serial of the product identification and tiled display blocks and the
    /// ContainerID. Checksums are recomputed so the blob stays valid. Blobs
    /// shorter than one 128-byte block are returned unchanged.
    static func redactedEDID(_ data: Data) -> Data {
        guard data.count >= 128 else { return data }
        var bytes = [UInt8](data)
        for index in 12...15 { bytes[index] = 0 }
        for offset in stride(from: 54, through: 108, by: 18)
        where bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 3] == 0xFF {
            for index in (offset + 5)..<(offset + 18) { bytes[index] = 0x20 }
        }
        setChecksum(&bytes, block: 0)
        let extensions = Int(bytes[126])
        if extensions > 0 {
            for block in 1...extensions where (block + 1) * 128 <= bytes.count && bytes[block * 128] == 0x70 {
                if redactDisplayID(&bytes, start: block * 128) { setChecksum(&bytes, block: block) }
            }
        }
        return Data(bytes)
    }

    /// Blanks the identifying fields of a DisplayID extension block that
    /// starts at `start`, fixing the section checksum. Returns true when
    /// anything changed.
    ///
    /// Layout: tag 0x70, version, section length N, product type, extension
    /// count, N bytes of data blocks, section checksum. Each data block is a
    /// tag, a revision, a payload length and the payload.
    private static func redactDisplayID(_ bytes: inout [UInt8], start: Int) -> Bool {
        let sectionEnd = start + 5 + Int(bytes[start + 2])
        guard sectionEnd < start + 127 else { return false }
        var changed = false
        func blank(_ range: Range<Int>) {
            for index in range where bytes[index] != 0 {
                bytes[index] = 0
                changed = true
            }
        }
        var offset = start + 5
        while offset + 3 <= sectionEnd {
            let tag = bytes[offset]
            let length = Int(bytes[offset + 2])
            let payload = offset + 3
            guard payload + length <= sectionEnd, tag != 0 || length > 0 else { break }
            switch tag {
            case 0x00, 0x20:
                // Product identification: OUI (3), product code (2), serial (4).
                if length >= 9 { blank((payload + 5)..<(payload + 9)) }
            case 0x12, 0x28:
                // Tiled display topology: the topology ID ends in a 4-byte serial.
                if length >= 22 { blank((payload + 18)..<(payload + 22)) }
            case 0x29:
                // ContainerID: a 16-byte UUID.
                blank(payload..<(payload + min(16, length)))
            default:
                break
            }
            offset = payload + length
        }
        if changed {
            let sum = bytes[(start + 1)..<sectionEnd].reduce(0) { ($0 + Int($1)) & 0xFF }
            bytes[sectionEnd] = UInt8((256 - sum) & 0xFF)
        }
        return changed
    }

    /// Sets byte 127 of a 128-byte EDID block so the block sums to zero.
    private static func setChecksum(_ bytes: inout [UInt8], block: Int) {
        let start = block * 128
        let sum = bytes[start..<(start + 127)].reduce(0) { ($0 + Int($1)) & 0xFF }
        bytes[start + 127] = UInt8((256 - sum) & 0xFF)
    }

    /// Serial numbers in the snapshot, as they could appear inside ids.
    private static func serialStrings(in snapshot: HostSnapshot) -> Set<String> {
        var serials = Set<String>()
        for display in snapshot.displays {
            if let serial = display.serialNumber, serial != 0 {
                serials.insert(String(serial))
                serials.insert(String(serial, radix: 16))
            }
        }
        for entry in snapshot.allDevices {
            if let serial = entry.device.serialNumber { serials.insert(serial) }
        }
        return serials
    }
}

/// Redacts one export. Created per export call, so stand-ins are numbered
/// from 1 in each export and the same identifier always gets the same
/// stand-in within it.
private final class Redactor {
    /// Serial numbers that may form a whole `:`-separated part of an id.
    /// Parts shorter than three characters are left alone: displays without
    /// a serial report 0 or 1, and such short values identify nothing.
    private let serials: Set<String>
    private var uids: [UInt64: UInt64] = [:]
    private var uuids: [String: Int] = [:]

    init(serials: Set<String>) {
        self.serials = Set(serials.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 })
    }

    // MARK: Stand-ins

    /// The stand-in for a Thunderbolt UID: the same top 16 bits (the vendor)
    /// with a running number below.
    func uid(_ value: UInt64) -> UInt64 {
        if let known = uids[value] { return known }
        let standIn = (value & 0xFFFF_0000_0000_0000) | UInt64(uids.count + 1)
        uids[value] = standIn
        return standIn
    }

    /// The stand-in for a UUID or container ID: the value with its hex
    /// digits replaced by a running number, keeping dashes, other characters
    /// and letter case. Keyed by `PowerParser.normalizedUUID`, so the dashed
    /// HPM form and the undashed SMC form of one UUID still match. A value
    /// without hex digits is returned unchanged.
    func uuid(_ value: String) -> String {
        guard let key = PowerParser.normalizedUUID(value) else { return value }
        let number = uuidNumber(key)
        let hexCount = value.filter(\.isHexDigit).count
        let isUpper = value.contains { $0.isLetter && $0.isUppercase }
        var digits = String(number, radix: 16, uppercase: isUpper)
        if digits.count < hexCount { digits = String(repeating: "0", count: hexCount - digits.count) + digits }
        var replacement = digits.makeIterator()
        var result = ""
        for character in value {
            if character.isHexDigit, let next = replacement.next() {
                result.append(next)
            } else if !character.isHexDigit {
                result.append(character)
            }
        }
        // A value with fewer hex digits than the number needs keeps the rest.
        while let next = replacement.next() { result.append(next) }
        return result
    }

    /// The stand-in for an identifier stored as bytes: the same length, all
    /// zero except the running number at the end. Shares its numbering with
    /// `uuid(_:)`, keyed by the bytes as hex.
    func uuid(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        var number = uuidNumber(data.map { TopologyText.hex(UInt64($0), width: 2) }.joined())
        var bytes = [UInt8](repeating: 0, count: data.count)
        var index = bytes.count - 1
        while number > 0, index >= 0 {
            bytes[index] = UInt8(number & 0xFF)
            number >>= 8
            index -= 1
        }
        return Data(bytes)
    }

    /// The running number for a normalized UUID, handed out on first sight.
    private func uuidNumber(_ key: String) -> Int {
        if let known = uuids[key] { return known }
        let number = uuids.count + 1
        uuids[key] = number
        return number
    }

    // MARK: Ids

    /// The id with serial parts redacted and Thunderbolt UIDs replaced.
    func id(_ id: String) -> String {
        var found = Set<String>()
        let shaped = IDShape.scrub(id, found: &found, display: { _ in Exporter.redactedText }, uid: { value, padded in
            let standIn = self.uid(value)
            return padded ? TopologyText.hex(standIn, width: 16) : String(standIn, radix: 16)
        })
        guard !serials.isEmpty else { return shaped }
        let parts = shaped.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        return parts.map { serials.contains($0) ? Exporter.redactedText : $0 }.joined(separator: ":")
    }

    // MARK: Values

    func device(_ device: DeviceNode) -> DeviceNode {
        var device = device
        device.id = id(device.id)
        if device.serialNumber != nil { device.serialNumber = Exporter.redactedText }
        device.properties = device.properties.map(bag)
        device.children = device.children.map(self.device)
        return device
    }

    func node(_ node: RawNode) -> RawNode {
        var node = node
        node.properties = bag(node.properties)
        return node
    }

    func bag(_ bag: PropertyBag) -> PropertyBag {
        PropertyBag(values(bag.values))
    }

    private func values(_ values: [String: PlistValue]) -> [String: PlistValue] {
        var result: [String: PlistValue] = [:]
        // Sorted, so stand-ins are numbered the same way on every run.
        for key in values.keys.sorted() {
            guard let value = values[key] else { continue }
            if Exporter.isSensitiveKey(key) {
                result[key] = .string(Exporter.redactedText)
            } else if Exporter.isUnitIdentifierKey(key) {
                result[key] = identifier(value, isUID: key.lowercased() == "uid")
            } else if key.lowercased() == "edid", case .data(let data) = value {
                result[key] = .data(Exporter.redactedEDID(data))
            } else {
                result[key] = self.value(value)
            }
        }
        return result
    }

    private func value(_ value: PlistValue) -> PlistValue {
        switch value {
        case .dict(let items): return .dict(values(items))
        case .array(let items): return .array(items.map(self.value))
        default: return value
        }
    }

    /// The stand-in for an identifier property. A UID becomes a number in
    /// whatever form it came (number, hex string or bytes), so a redacted
    /// capture still parses to the same `tb:` ids; a value that cannot hold
    /// a stand-in becomes "REDACTED".
    private func identifier(_ value: PlistValue, isUID: Bool) -> PlistValue {
        if isUID, let number = value.int64Value {
            return .int(Int64(bitPattern: uid(UInt64(bitPattern: number))))
        }
        switch value {
        case .string(let text): return .string(uuid(text))
        case .data(let data): return .data(uuid(data))
        case .dict, .array: return self.value(value)
        default: return .string(Exporter.redactedText)
        }
    }
}

/// Finds identifiers in ids by their shape.
enum IDShape {
    /// Replaces, in a `:`-separated id:
    /// - the serial after `display:<vendor>:<product>:` (decimal, at least
    ///   three digits; a `cg…` stand-in for a missing serial is kept), via
    ///   `display`;
    /// - the hex UID after `tb:` (a `tb:reg-…` registry fallback is kept), via
    ///   `uid`, which also learns whether the hex was padded to 16 digits.
    ///
    /// A `#…` suffix that makes a repeated id unique is kept. Every replaced
    /// value is added to `found`.
    static func scrub(_ id: String, found: inout Set<String>, display: (String) -> String,
                      uid: (UInt64, Bool) -> String) -> String {
        var parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return id }
        for i in parts.indices {
            if parts[i] == "display", i + 3 < parts.count {
                let (head, tail) = splitSuffix(parts[i + 3])
                if head.count >= 3, head.allSatisfy(\.isASCIIDigit) {
                    found.insert(head)
                    parts[i + 3] = display(head) + tail
                }
            } else if parts[i] == "tb", i + 1 < parts.count {
                let (head, tail) = splitSuffix(parts[i + 1])
                if (1...16).contains(head.count), head.allSatisfy(\.isHexDigit), let value = UInt64(head, radix: 16) {
                    found.insert(head)
                    found.insert(String(value, radix: 16))
                    parts[i + 1] = uid(value, head.count == 16) + tail
                }
            }
        }
        return parts.joined(separator: ":")
    }

    /// "204588#cg3" → ("204588", "#cg3").
    private static func splitSuffix(_ part: String) -> (String, String) {
        guard let hash = part.firstIndex(of: "#") else { return (part, "") }
        return (String(part[..<hash]), String(part[hash...]))
    }

    /// The text with every whole word (a run of letters and digits) that
    /// equals one of `words`, ignoring case, replaced by "REDACTED".
    static func removing(_ words: Set<String>, from text: String) -> String {
        guard !words.isEmpty else { return text }
        let lowered = Set(words.map { $0.lowercased() })
        var result = ""
        var word = ""
        func flush() {
            result += lowered.contains(word.lowercased()) ? Exporter.redactedText : word
            word = ""
        }
        for character in text {
            if character.isLetter || character.isNumber {
                word.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
