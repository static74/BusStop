import Foundation

/// Export formats offered by the app and the CLI.
///
/// JSON output is pretty-printed with sorted keys and ISO-8601 dates, so the
/// same input always produces the same bytes. Redaction is on by default and
/// is described in `Exporter+Redaction.swift`.
public enum Exporter {
    /// The text that replaces redacted values.
    public static let redactedText = "REDACTED"

    /// Pretty-printed, key-sorted JSON of the snapshot. When `redact` is true,
    /// serial numbers and other identifying values are removed (see
    /// `redacted(_:)` for the list).
    public static func json(_ snapshot: HostSnapshot, redact: Bool = true) throws -> Data {
        try makeEncoder().encode(redact ? redacted(snapshot) : snapshot)
    }

    /// Pretty-printed, key-sorted JSON of a raw capture (for bug reports and
    /// test fixtures). When `redact` is true, serials are redacted in every
    /// property bag and the computer name is dropped.
    public static func rawJSON(_ raw: RawSnapshot, redact: Bool = true) throws -> Data {
        try makeEncoder().encode(redact ? redacted(raw) : raw)
    }

    /// Decodes a raw capture produced by `rawJSON`.
    ///
    /// Captures written by older or hand-edited files may leave out lists and
    /// flags; those default to empty or false. The capture date, the machine
    /// model and registry IDs are still required.
    public static func decodeRaw(_ data: Data) throws -> RawSnapshot {
        let decoder = makeDecoder()
        do {
            return try decoder.decode(RawSnapshot.self, from: data)
        } catch let original {
            guard let value = try? JSONDecoder().decode(PlistValue.self, from: data),
                  case .dict(let object) = value else { throw original }
            let completed = RawDefaults.snapshot(object)
            guard let normalized = try? JSONEncoder().encode(PlistValue.dict(completed)),
                  let raw = try? decoder.decode(RawSnapshot.self, from: normalized) else { throw original }
            return raw
        }
    }

    // MARK: Coders

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Fills in members a raw capture may lack, so `decodeRaw` accepts files
/// written before a field existed.
enum RawDefaults {
    typealias Object = [String: PlistValue]

    static func snapshot(_ object: Object) -> Object {
        var result = object
        fill(&result, "schemaVersion", .int(Int64(RawSnapshot.currentSchemaVersion)))
        for key in ["portNodes", "usbDevices", "thunderboltSwitches", "smcChannels", "displays", "captureNotes"] {
            fill(&result, key, .array([]))
        }
        fill(&result, "portControllerUUIDs", .dict([:]))
        if case .dict(var machine)? = result["machine"] {
            fill(&machine, "osVersion", .string(""))
            fill(&machine, "hasBattery", .bool(false))
            result["machine"] = .dict(machine)
        }
        map(&result, "portNodes", node)
        map(&result, "usbDevices") { device in
            var device = device
            if case .dict(let inner)? = device["node"] { device["node"] = .dict(node(inner)) }
            map(&device, "ancestry", ancestor)
            return device
        }
        map(&result, "thunderboltSwitches") { sw in
            var sw = sw
            if case .dict(let inner)? = sw["node"] { sw["node"] = .dict(node(inner)) }
            fill(&sw, "ports", .array([]))
            fill(&sw, "ancestry", .array([]))
            map(&sw, "ports", node)
            map(&sw, "ancestry", ancestor)
            return sw
        }
        map(&result, "displays") { display in
            var display = display
            fill(&display, "isBuiltin", .bool(false))
            fill(&display, "isMain", .bool(false))
            return display
        }
        return result
    }

    static func node(_ object: Object) -> Object {
        var result = object
        fill(&result, "className", .string(""))
        fill(&result, "classChain", .array([]))
        fill(&result, "name", .string(""))
        fill(&result, "properties", .dict([:]))
        return result
    }

    static func ancestor(_ object: Object) -> Object {
        var result = object
        fill(&result, "className", .string(""))
        fill(&result, "name", .string(""))
        return result
    }

    private static func fill(_ object: inout Object, _ key: String, _ value: PlistValue) {
        if object[key] == nil { object[key] = value }
    }

    /// Applies `transform` to every dictionary in the array at `key`.
    private static func map(_ object: inout Object, _ key: String, _ transform: (Object) -> Object) {
        guard case .array(let items)? = object[key] else { return }
        object[key] = .array(items.map { item in
            if case .dict(let inner) = item { return .dict(transform(inner)) }
            return item
        })
    }
}
