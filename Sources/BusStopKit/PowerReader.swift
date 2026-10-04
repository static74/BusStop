import BusStopCore
import Foundation
import IOKit
import IOKit.ps

/// Reads battery and charger state: selected `AppleSmartBattery` keys and
/// the power-source API's external adapter details.
enum PowerReader {
    /// Selected `AppleSmartBattery` keys, read one at a time. Nil when the
    /// service does not exist (some virtual machines).
    static func battery() -> PropertyBag? {
        guard let entry = RegistryEntry.firstMatching(className: "AppleSmartBattery") else { return nil }
        return PropertyBag(entry.properties(keys: RegistryKeys.battery))
    }

    /// `IOPSCopyExternalPowerAdapterDetails()`; nil when no adapter is attached.
    static func adapter() -> PropertyBag? {
        guard let unmanaged = IOPSCopyExternalPowerAdapterDetails() else { return nil }
        let bag = PlistBridge.bag(from: unmanaged.takeRetainedValue())
        return bag.isEmpty ? nil : bag
    }

    /// Whether the power-source API lists an internal battery.
    static func powerSourcesListInternalBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else { return false }
        let count = CFArrayGetCount(list)
        guard count > 0 else { return false }
        for index in 0..<min(count, 64) {
            guard let pointer = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() else { continue }
            let bag = PlistBridge.bag(from: description)
            if bag.string("Type") == "InternalBattery" { return true }
        }
        return false
    }
}
