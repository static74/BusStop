import BusStopCore
import Foundation

/// Reads ports, devices, power and displays from IOKit into a `RawSnapshot`.
///
/// Everything here is a read: no user clients are opened except the SMC
/// (read selectors only). Call from a background queue; a capture takes a few
/// milliseconds to a few tens of milliseconds.
public enum RegistryCapture {
    /// Captures a full snapshot. Never throws; partial failures are recorded in
    /// `captureNotes`.
    public static func capture(includeSMC: Bool = true) -> RawSnapshot {
        fatalError("not implemented")
    }

    /// Model, chip, OS version and battery presence.
    public static func machineInfo() -> MachineInfo {
        fatalError("not implemented")
    }
}
