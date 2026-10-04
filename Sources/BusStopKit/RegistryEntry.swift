// Portions adapted from WhatPort (MIT License, © 2025 Darryl Morley).

import BusStopCore
import Foundation
import IOKit
import os

/// Owns one IOKit object reference (`io_object_t`, `io_registry_entry_t`,
/// `io_iterator_t`, …) and releases it exactly once, when the handle is
/// deallocated.
final class IOObjectHandle {
    let object: io_object_t

    /// Takes ownership of `object`. Returns nil for the null object, which
    /// needs no release.
    init?(adopting object: io_object_t) {
        guard object != 0 else { return nil }
        self.object = object
    }

    deinit {
        IOObjectRelease(object)
    }
}

/// Registry planes Bus Stop reads.
enum RegistryPlane {
    static let service = "IOService"
    static let port = "IOPort"
    static let deviceTree = "IODeviceTree"
}

/// A retained IORegistry entry with the read operations the capture needs.
///
/// Every accessor tolerates failure (a service can terminate mid-read) and
/// returns nil or an empty value instead of trapping. Entries returned by
/// `parent`, `children` and `matching` are owned and released automatically.
struct RegistryEntry {
    let handle: IOObjectHandle

    var raw: io_registry_entry_t { handle.object }

    /// Takes ownership of `raw`. Returns nil for the null entry.
    init?(adopting raw: io_registry_entry_t) {
        guard let handle = IOObjectHandle(adopting: raw) else { return nil }
        self.handle = handle
    }

    // MARK: Identity

    /// `IORegistryEntryGetRegistryEntryID`.
    var entryID: UInt64? {
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(raw, &id) == KERN_SUCCESS else { return nil }
        return id
    }

    /// `IOObjectGetClass`.
    var className: String? {
        Self.readName { IOObjectGetClass(raw, $0) }
    }

    /// `IORegistryEntryGetName`.
    var name: String? {
        Self.readName { IORegistryEntryGetName(raw, $0) }
    }

    /// `IORegistryEntryGetLocationInPlane`; nil when the entry has no
    /// location in that plane.
    func location(in plane: String) -> String? {
        let location = Self.readName { IORegistryEntryGetLocationInPlane(raw, plane, $0) }
        guard let location, !location.isEmpty else { return nil }
        return location
    }

    /// The location in the first of `planes` that has one.
    func location(inFirstOf planes: [String]) -> String? {
        for plane in planes {
            if let location = location(in: plane) { return location }
        }
        return nil
    }

    /// `IOObjectConformsTo`: whether the entry's class is `className` or a
    /// subclass of it.
    func conforms(to className: String) -> Bool {
        IOObjectConformsTo(raw, className) != 0
    }

    /// Whether the entry is attached in `plane`.
    func isInPlane(_ plane: String) -> Bool {
        IORegistryEntryInPlane(raw, plane) != 0
    }

    // MARK: Navigation

    /// `IORegistryEntryGetParentEntry` in `plane`.
    func parent(in plane: String) -> RegistryEntry? {
        var parent: io_registry_entry_t = 0
        let result = IORegistryEntryGetParentEntry(raw, plane, &parent)
        // Adopt before checking the result so a stray reference is released.
        let entry = RegistryEntry(adopting: parent)
        guard result == KERN_SUCCESS else { return nil }
        return entry
    }

    /// Direct children in `plane`, re-walked if the registry changes during
    /// the walk.
    func children(in plane: String) -> [RegistryEntry] {
        var iterator: io_iterator_t = 0
        let result = IORegistryEntryGetChildIterator(raw, plane, &iterator)
        guard let handle = IOObjectHandle(adopting: iterator), result == KERN_SUCCESS else { return [] }
        return Self.drain(handle)
    }

    /// The root of the registry.
    static func root() -> RegistryEntry? {
        RegistryEntry(adopting: IORegistryGetRootEntry(kIOMainPortDefault))
    }

    /// All services matching `className` (including subclasses).
    static func matching(className: String) -> [RegistryEntry] {
        guard let matching = IOServiceMatching(className) else { return [] }
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard let handle = IOObjectHandle(adopting: iterator), result == KERN_SUCCESS else { return [] }
        return drain(handle)
    }

    /// The first service matching `className`.
    static func firstMatching(className: String) -> RegistryEntry? {
        guard let matching = IOServiceMatching(className) else { return nil }
        return RegistryEntry(adopting: IOServiceGetMatchingService(kIOMainPortDefault, matching))
    }

    /// Most entries taken from one iterator. Guards against a runaway walk.
    static let maxIteratorItems = 20_000

    /// Drains an iterator. `IOIteratorNext` returns 0 both at the end and when
    /// the registry changed under the walk, so the iterator is checked with
    /// `IOIteratorIsValid` afterwards; an invalidated walk is discarded, the
    /// iterator reset and the walk repeated, up to `maxAttempts` times. The
    /// last attempt's results are kept even if it was also invalidated.
    static func drain(_ iterator: IOObjectHandle, maxAttempts: Int = 3) -> [RegistryEntry] {
        var results: [RegistryEntry] = []
        let attempts = max(1, maxAttempts)
        for attempt in 1...attempts {
            results = []
            while results.count < maxIteratorItems {
                let next = IOIteratorNext(iterator.object)
                guard let entry = RegistryEntry(adopting: next) else { break }
                results.append(entry)
            }
            if IOIteratorIsValid(iterator.object) != 0 || attempt == attempts { break }
            // Dropping `results` releases the discarded handles.
            IOIteratorReset(iterator.object)
        }
        return results
    }

    // MARK: Properties

    /// One property, read on its own (`IORegistryEntryCreateCFProperty`).
    /// Safe on services that may be torn down while being read.
    func property(_ key: String) -> PlistValue? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(raw, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return PlistBridge.value(from: unmanaged.takeRetainedValue())
    }

    /// The given keys, each read on its own. Missing keys are left out.
    func properties(keys: [String]) -> [String: PlistValue] {
        var result: [String: PlistValue] = [:]
        for key in keys {
            if let value = property(key) { result[key] = value }
        }
        return result
    }

    /// Every property in one call (`IORegistryEntryCreateCFProperties`).
    ///
    /// Use only on long-lived services (port controllers): on a service that
    /// is being torn down the kernel can return a malformed blob that aborts
    /// the process inside `IOCFUnserializeBinary` (WhatCable issue #181).
    func allProperties() -> [String: PlistValue]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(raw, &unmanaged, kCFAllocatorDefault, 0)
        let dictionary = unmanaged?.takeRetainedValue()
        guard result == KERN_SUCCESS, let dictionary else { return nil }
        return PlistBridge.bag(from: dictionary).values
    }

    /// `IORegistryEntrySearchCFProperty`: the property on this entry or, when
    /// `parents` is true, on the nearest ancestor in `plane` that has it.
    func searchProperty(_ key: String, plane: String, parents: Bool) -> PlistValue? {
        var options = IOOptionBits(kIORegistryIterateRecursively)
        if parents { options |= IOOptionBits(kIORegistryIterateParents) }
        guard let value = IORegistryEntrySearchCFProperty(raw, plane, key as CFString, kCFAllocatorDefault, options) else {
            return nil
        }
        return PlistBridge.value(from: value)
    }

    // MARK: Helpers

    /// Size of `io_name_t`.
    private static let nameBufferSize = 128

    /// Reads a NUL-terminated `io_name_t` filled by `fill`.
    private static func readName(_ fill: (UnsafeMutablePointer<CChar>) -> kern_return_t) -> String? {
        // One spare byte guarantees termination even if the callee fills all 128.
        var buffer = [CChar](repeating: 0, count: nameBufferSize + 1)
        let result = buffer.withUnsafeMutableBufferPointer { pointer -> kern_return_t in
            guard let base = pointer.baseAddress else { return KERN_FAILURE }
            return fill(base)
        }
        guard result == KERN_SUCCESS else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Superclass chains of IOKit classes (`IOObjectCopySuperclassForClass`),
/// cached per class name for the life of the process.
enum ClassHierarchy {
    private static let cache = OSAllocatedUnfairLock<[String: [String]]>(initialState: [:])

    /// Most classes recorded in one chain.
    static let maxChainLength = 48

    /// The class itself followed by its superclasses, nearest first.
    static func chain(for className: String) -> [String] {
        if let cached = cache.withLock({ $0[className] }) { return cached }
        var chain = [className]
        var current = className
        while chain.count < maxChainLength {
            guard let unmanaged = IOObjectCopySuperclassForClass(current as CFString) else { break }
            let superclass = unmanaged.takeRetainedValue() as String
            guard !superclass.isEmpty, !chain.contains(superclass) else { break }
            chain.append(superclass)
            current = superclass
        }
        let result = chain
        cache.withLock { $0[className] = result }
        return result
    }
}
