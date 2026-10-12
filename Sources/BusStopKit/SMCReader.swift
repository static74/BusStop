// Portions adapted from WhatPort (MIT License, © 2025 Darryl Morley).

import BusStopCore
import Foundation
import IOKit

/// Reads the per-port USB-C power channels (`D1`…`D4`) from the System
/// Management Controller through the `AppleSMC` user client.
///
/// Only the read selectors are used. One connection is opened lazily, shared
/// by all callers behind one lock, and closed when the reader is deallocated.
/// Any failure leaves the result empty and is reported as a note; the reader
/// never traps.
final class SMCReader: @unchecked Sendable {
    /// The process-wide reader `RegistryCapture` uses.
    static let shared = SMCReader()

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    /// Set after a failed open so later captures do not retry on every poll.
    private var openFailure: String?
    /// The first failed kernel call of the read in progress.
    private var callFailure: kern_return_t?

    init() {}

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    /// Whether `SMCParamStruct` has the 80-byte layout the kernel expects.
    static var hasExpectedLayout: Bool {
        MemoryLayout<SMCParamStruct>.stride == 80 && MemoryLayout<SMCParamStruct>.size == 80
    }

    /// Reads channels 1…4. Returns the channels found and, when the SMC could
    /// not be used at all, a note saying why.
    func readChannels() -> (channels: [SMCChannel], note: String?) {
        guard Self.hasExpectedLayout else {
            return ([], "SMC skipped: SMCParamStruct is \(MemoryLayout<SMCParamStruct>.stride) bytes, expected 80")
        }
        lock.lock()
        defer { lock.unlock() }
        if let failure = openLocked() {
            return ([], failure)
        }
        callFailure = nil
        let channels = Self.buildChannels(readKey: { readKeyLocked($0) })
        if let failure = callFailure {
            // Fail closed: a kernel error means none of this read can be
            // trusted. Drop the connection so the next read reopens it.
            closeLocked()
            return ([], "SMC read failed: IOConnectCallStructMethod returned \(Self.hex(failure))")
        }
        return (channels, nil)
    }

    /// Closes the connection; the next read reopens it.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
        openFailure = nil
    }

    private func closeLocked() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    private static func hex(_ result: kern_return_t) -> String {
        "0x" + String(UInt32(bitPattern: result), radix: 16)
    }

    // MARK: Channel rules

    /// One SMC key as read: its four-character type and raw bytes.
    struct KeyValue: Equatable {
        var type: String
        var bytes: [UInt8]
    }

    /// Builds channels from a key reader. A channel is kept when any of its
    /// identity or power keys exist. Separated from the kernel calls so it can
    /// be tested with recorded bytes.
    static func buildChannels(readKey: (String) -> KeyValue?) -> [SMCChannel] {
        var channels: [SMCChannel] = []
        for index in 1...4 {
            let uuid = readKey("D\(index)UI").flatMap { decodeHex($0.bytes) }
            let volts = readKey("D\(index)JV").flatMap(decodeFloat)
            let amps = readKey("D\(index)JI").flatMap(decodeFloat)
            let present = readKey("D\(index)PR").flatMap { $0.bytes.first.map { $0 != 0 } }
            guard uuid != nil || volts != nil || amps != nil || present != nil else { continue }
            let contract = readKey("D\(index)MP").flatMap { decodeBigEndianInt($0.bytes) }
            let label = readKey("D\(index)DE").flatMap { decodeString($0.bytes) }
            channels.append(SMCChannel(
                index: index,
                uuid: uuid,
                volts: volts,
                amps: amps,
                present: present,
                contractMilliwatts: contract,
                label: label
            ))
        }
        return channels
    }

    /// A little-endian IEEE float (`flt `). Non-finite values are dropped.
    static func decodeFloat(_ value: KeyValue) -> Double? {
        guard value.type == "flt ", value.bytes.count >= 4 else { return nil }
        let bits = UInt32(value.bytes[0]) | UInt32(value.bytes[1]) << 8
            | UInt32(value.bytes[2]) << 16 | UInt32(value.bytes[3]) << 24
        let float = Float(bitPattern: bits)
        return float.isFinite ? Double(float) : nil
    }

    /// A big-endian unsigned integer of 1…8 bytes (`ui8 `, `ui16`, `ui32`).
    static func decodeBigEndianInt(_ bytes: [UInt8]) -> Int? {
        guard !bytes.isEmpty, bytes.count <= 8 else { return nil }
        let value = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Int(exactly: value)
    }

    /// Raw bytes as lowercase hex (`DxUI`, the HPM controller UUID without
    /// dashes). All-zero means "no controller" and reads as nil.
    static func decodeHex(_ bytes: [UInt8]) -> String? {
        guard bytes.contains(where: { $0 != 0 }) else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// A NUL-padded string (`ch8*`). Empty reads as nil.
    static func decodeString(_ bytes: [UInt8]) -> String? {
        let trimmed = bytes.prefix { $0 != 0 }
        guard !trimmed.isEmpty else { return nil }
        let string = String(decoding: trimmed, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return string.isEmpty ? nil : string
    }

    /// Packs a four-character key into its FourCC value, first character in
    /// the most significant byte.
    static func fourCC(_ key: String) -> UInt32? {
        let scalars = Array(key.unicodeScalars)
        guard scalars.count == 4 else { return nil }
        var value: UInt32 = 0
        for scalar in scalars {
            guard scalar.value <= 0xFF else { return nil }
            value = (value << 8) | scalar.value
        }
        return value
    }

    /// The four characters of a FourCC value.
    static func fourCCString(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> UInt32($0)) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Kernel calls (lock held)

    private static let selectorHandleYPCEvent: UInt32 = 2
    private static let commandReadKey: UInt8 = 5
    private static let commandGetKeyInfo: UInt8 = 9

    /// Opens the user client if needed. Returns a failure note, or nil.
    private func openLocked() -> String? {
        if connection != 0 { return nil }
        if let openFailure { return openFailure }
        guard let service = RegistryEntry.firstMatching(className: "AppleSMC") else {
            openFailure = "SMC unavailable: no AppleSMC service"
            return openFailure
        }
        var newConnection: io_connect_t = 0
        let result = IOServiceOpen(service.raw, mach_task_self_, 0, &newConnection)
        guard result == KERN_SUCCESS, newConnection != 0 else {
            openFailure = "SMC unavailable: IOServiceOpen failed (\(Self.hex(result)))"
            return openFailure
        }
        connection = newConnection
        return nil
    }

    /// Reads one key: its size and type (command 9), then its value
    /// (command 5). A key the SMC does not have reads as nil; a failed kernel
    /// call also reads as nil and is recorded in `callFailure`.
    private func readKeyLocked(_ key: String) -> KeyValue? {
        guard callFailure == nil, let code = Self.fourCC(key) else { return nil }

        var infoRequest = SMCParamStruct()
        infoRequest.key = code
        infoRequest.data8 = Self.commandGetKeyInfo
        guard let info = callLocked(&infoRequest), info.result == 0 else { return nil }
        let size = info.keyInfo.dataSize
        guard size > 0, size <= 32 else { return nil }

        var readRequest = SMCParamStruct()
        readRequest.key = code
        readRequest.keyInfo.dataSize = size
        readRequest.keyInfo.dataType = info.keyInfo.dataType
        readRequest.data8 = Self.commandReadKey
        guard var value = callLocked(&readRequest), value.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: &value.bytes) { Array($0.prefix(Int(size))) }
        return KeyValue(type: Self.fourCCString(info.keyInfo.dataType), bytes: bytes)
    }

    private func callLocked(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        guard connection != 0 else { return nil }
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            Self.selectorHandleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == KERN_SUCCESS else {
            if callFailure == nil { callFailure = result }
            return nil
        }
        return output
    }
}

// MARK: - AppleSMC user-client ABI
//
// These mirror the C structs used by powermetrics and smcFanControl. Field
// order and widths must not change: the kernel reads the struct at fixed
// offsets and rejects any size other than 80 bytes.

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimit = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    /// C pads `keyInfo` to 12 bytes; Swift would pack `result` into that
    /// padding and shrink the struct to 76 bytes. This field restores the C
    /// offsets.
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
