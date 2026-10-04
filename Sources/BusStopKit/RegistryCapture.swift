import BusStopCore
import Darwin
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
        capture(includeSMC: includeSMC, smc: SMCReader.shared)
    }

    /// Model, chip, OS version and battery presence.
    public static func machineInfo() -> MachineInfo {
        machineInfo(battery: PowerReader.battery())
    }

    /// Captures with an explicit SMC reader (tests, the live monitor).
    static func capture(includeSMC: Bool, smc: SMCReader) -> RawSnapshot {
        var notes: [String] = []
        let capturedAt = Date()
        let rootID = RegistryEntry.root()?.entryID

        let battery = PowerReader.battery()
        if battery == nil {
            notes.append("AppleSmartBattery service not found")
        }
        let machine = machineInfo(battery: battery)
        let ports = PortNodeReader.read(rootID: rootID, notes: &notes)
        let usbDevices = USBDeviceReader.read(rootID: rootID)
        let switches = ThunderboltReader.read()
        let adapter = PowerReader.adapter()

        var channels: [SMCChannel] = []
        if includeSMC {
            let reading = smc.readChannels()
            channels = reading.channels
            if let note = reading.note { notes.append(note) }
        }

        let displays = DisplayReader.read(notes: &notes)

        return RawSnapshot(
            capturedAt: capturedAt,
            machine: machine,
            portNodes: ports.nodes,
            portControllerUUIDs: ports.controllerUUIDs,
            usbDevices: usbDevices,
            thunderboltSwitches: switches,
            battery: battery,
            adapter: adapter,
            smcChannels: channels,
            displays: displays,
            captureNotes: notes
        )
    }

    static func machineInfo(battery: PropertyBag?) -> MachineInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = version.patchVersion > 0
            ? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            : "\(version.majorVersion).\(version.minorVersion)"
        let hasBattery = battery?.bool("BatteryInstalled") ?? PowerReader.powerSourcesListInternalBattery()
        return MachineInfo(
            model: sysctlString("hw.model") ?? "Mac",
            targetType: sysctlString("hw.targettype"),
            chip: sysctlString("machdep.cpu.brand_string"),
            osVersion: osVersion,
            osBuild: sysctlString("kern.osversion"),
            hasBattery: hasBattery,
            computerName: nil
        )
    }

    /// A string `sysctl` value, or nil when the name does not exist.
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size <= 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
