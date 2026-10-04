import Foundation

/// MacBook Pro 14-inch (M5) on battery with nothing plugged in.
///
/// The battery is at 64% and discharging at about 9 W. Like the M5
/// MacBook Pros WhatPort measured, this Mac numbers its USB-C ports 1, 2
/// and 4, so the right-hand port is labelled by rank from the catalogue.
enum DemoUnplugged {
    static let model = "Mac17,2"

    static func raw(at date: Date, tick: Int) -> RawSnapshot {
        let wave = DemoWave(tick: tick)
        var r = DemoRegistry()
        let uuids = (magSafe: DemoPower.uuid(seed: 0xB0_0011), port1: DemoPower.uuid(seed: 0xB0_0021),
                     port2: DemoPower.uuid(seed: 0xB0_0022), port4: DemoPower.uuid(seed: 0xB0_0024))
        let flow = DemoPowerFlow(systemPowerIn: 0, systemVoltageIn: 0,
                                 systemLoad: DemoPower.milliwatts(wave.value(9_100, amplitude: 0.05, phase: 0.7)))

        let thunderboltPort = ["CC", "USB2", "USB3", "DisplayPort", "CIO"]
        r.hpmPort(number: 1, type: PortKey.magSafeType, typeDescription: "MagSafe 3",
                  className: "AppleHPMInterfaceType11", uuid: uuids.magSafe,
                  state: DemoPortState(supported: ["CC"], features: ["LDCM"], plugEvents: 388))
        r.hpmPort(number: 1, uuid: uuids.port1, state: DemoPortState(supported: thunderboltPort, plugEvents: 95))
        r.hpmPort(number: 2, uuid: uuids.port2, state: DemoPortState(supported: thunderboltPort, plugEvents: 140))
        r.hpmPort(number: 4, uuid: uuids.port4, state: DemoPortState(supported: thunderboltPort, plugEvents: 27))
        r.hdmiPort(hotPlug: false)

        for (acio, socket) in [(0, 1), (1, 2), (2, 4)] {
            r.hostSwitch(acio: acio, socket: socket, uid: 0x05AC_9E04_17B5_0000 + Int64(socket),
                         modelName: "MacBook Pro", link: nil)
        }

        let smc = [
            DemoPower.channel(1, uuid: uuids.port1, volts: 0, amps: 0),
            DemoPower.channel(2, uuid: uuids.port2, volts: 0, amps: 0),
            DemoPower.channel(3, uuid: uuids.port4, volts: 0, amps: 0),
            DemoPower.channel(4, uuid: uuids.magSafe, volts: 0, amps: 0),
        ]

        let battery = DemoPower.laptopBattery(percent: 64, charging: false, adapter: nil, flow: flow, voltage: 11_918,
                                              cycleCount: 212, minutesRemaining: 318)

        let displays = [
            RawDisplay(id: 1, name: "Built-in Liquid Retina XDR Display", vendorID: 0x610, productID: 0xA051,
                       isBuiltin: true, isMain: true, pixelWidth: 3024, pixelHeight: 1964, refreshHz: 120),
        ]

        return RawSnapshot(capturedAt: date,
                           machine: MachineInfo(model: model, chip: "Apple M5", osVersion: "27.0", hasBattery: true),
                           portNodes: r.portNodes, portControllerUUIDs: r.controllerUUIDs,
                           thunderboltSwitches: r.switches, battery: battery, smcChannels: smc, displays: displays)
    }
}
