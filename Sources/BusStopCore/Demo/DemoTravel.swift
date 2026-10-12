import Foundation

/// MacBook Air 13-inch (M4) on the road.
///
/// - MagSafe: empty.
/// - Left Center USB-C (port 1): Apple 70W USB-C Power Adapter on a
///   20 V × 3.5 A contract. The port's USB-PD power source is the winner.
/// - Left Front USB-C (port 2): an iPhone 17 Pro on a 240 W charge cable,
///   which carries USB 2 data only, so the iPhone (a USB 3 device) syncs at
///   480 Mb/s. The Mac charges it at about 4.5 W (`PowerOutDetails`).
/// - The battery is at 82% and charging.
enum DemoTravel {
    static let model = "Mac16,12"
    static let soc = "T8132"

    static func raw(at date: Date, tick: Int) -> RawSnapshot {
        let wave = DemoWave(tick: tick)
        var r = DemoRegistry()
        let uuids = (magSafe: DemoPower.uuid(seed: 0x7A_0011), port1: DemoPower.uuid(seed: 0x7A_0021),
                     port2: DemoPower.uuid(seed: 0x7A_0022))

        // Power: about 31 W in at 20 V, about 4.5 W out to the iPhone.
        let phoneWatts = wave.value(4.5, amplitude: 0.035, phase: 1.1)
        let flow = DemoPowerFlow(systemPowerIn: DemoPower.milliwatts(wave.value(31_200, amplitude: 0.03, phase: 0.2)),
                                 systemVoltageIn: DemoPower.milliwatts(wave.value(19_960, amplitude: 0.002, phase: 0.8)),
                                 systemLoad: DemoPower.milliwatts(wave.value(7_100, amplitude: 0.05, phase: 2.4)
                                     + phoneWatts * 1000))

        r.hpmPort(number: 1, type: PortKey.magSafeType, typeDescription: "MagSafe 3",
                  className: "AppleHPMInterfaceType11", uuid: uuids.magSafe,
                  state: DemoPortState(supported: ["CC"], features: ["LDCM"], plugEvents: 6))

        // Port 1: the 70 W charger.
        let adapter = DemoAdapter.apple70W
        let port1 = r.hpmPort(number: 1, uuid: uuids.port1,
                              state: DemoPortState(supported: ["CC", "USB2", "USB3", "DisplayPort", "CIO"],
                                                   active: ["CC"], features: ["TRM", "LDCM", "Power In"],
                                                   plugEvents: 233))
        let chargerPartner = r.partner(on: port1)
        r.appleCharger(on: port1, sop: chargerPartner, name: adapter.name, model: adapter.model,
                       serial: adapter.serial)
        r.powerIn(on: port1, sources: [
            ("USB-PD", adapter.powerSourceOptions(uuidSeed: 0x7A_1000)),
            ("Brick ID", [DemoRegistry.powerOption(millivolts: 5_000, milliamps: 1_500,
                                                   uuid: DemoPower.uuid(seed: 0x7A_1100))]),
            ("TypeC", [DemoRegistry.powerOption(millivolts: 5_000, milliamps: 3_000,
                                                uuid: DemoPower.uuid(seed: 0x7A_1200))]),
        ], winner: "USB-PD")

        // Port 2: the iPhone on a USB 2 cable with an e-marker (5 A, 2 m).
        let port2 = r.hpmPort(number: 2, uuid: uuids.port2,
                              state: DemoPortState(supported: ["CC", "USB2", "USB3", "DisplayPort", "CIO"],
                                                   active: ["CC", "USB2"], plugEvents: 121))
        r.partner(on: port2)
        r.cableMarker(on: port2, typeDescription: "Passive Cable", vdos: [
            DemoCableVDO.passiveHeader(vendorID: 0x05AC), 0,
            DemoCableVDO.product(productID: 0x7306), DemoCableVDO.passiveCable(speed: 0, fiveAmps: true, latency: 2),
        ])
        let iPhoneSerial = "00008150-001A2C3E1E40801C"
        let port2USB2 = r.transport("USB2", on: port2, parent: port2.id, active: true,
                                    extra: DemoRegistry.usb2Keys(product: "iPhone", manufacturer: "Apple Inc.",
                                                                 vendorID: 0x05AC, productID: 0x12A8,
                                                                 serial: iPhoneSerial))

        let drd1 = r.nativeController(drd: 1, soc: soc, port: port2, hpm: 1)
        r.usbRoot(DemoUSBDevice(
            name: "iPhone", vendorName: "Apple Inc.", vendorID: 0x05AC, productID: 0x12A8, bcdDevice: 0x1A01,
            bcdUSB: 0x0320, speed: LinkDecoding.highSpeed, allocation: 900, serial: iPhoneSerial,
            interfaces: [RawUSBInterface(interfaceClass: 6, interfaceSubClass: 1, interfaceProtocol: 1, name: "PTP"),
                         RawUSBInterface(interfaceClass: 0xFF, interfaceSubClass: 0xFE, interfaceProtocol: 2,
                                         name: "Apple USB Multiplexor"),
                         RawUSBInterface(interfaceClass: 0xFF, interfaceSubClass: 0xFD, interfaceProtocol: 1,
                                         name: "Apple Mobile Device Ethernet")]),
            on: drd1, transport: port2USB2)

        // Thunderbolt 4 host switches; idle lanes keep their 10 Gb/s defaults.
        let idle = DemoThunderboltLink(speedCode: 0x8, widthCode: 0x1, supportedMask: 0xC)
        r.hostSwitch(acio: 0, socket: 1, uid: 0x05AC_51E2_9A70_0001, modelName: "MacBook Air", type: 5, link: nil,
                     idleLink: idle)
        r.hostSwitch(acio: 1, socket: 2, uid: 0x05AC_51E2_9A70_0002, modelName: "MacBook Air", type: 5, link: nil,
                     idleLink: idle)

        let battery = DemoPower.laptopBattery(
            percent: 82, charging: true, adapter: adapter, flow: flow, voltage: 12_712, cycleCount: 148,
            minutesRemaining: 34,
            powerOut: [DemoPower.powerOut(port: 2, milliwatts: DemoPower.milliwatts(phoneWatts * 1000),
                                          millivolts: 5_000)])

        let displays = [
            RawDisplay(id: 1, name: "Built-in Liquid Retina Display", vendorID: 0x610, productID: 0xA04F,
                       isBuiltin: true, isMain: true, pixelWidth: 2560, pixelHeight: 1664, refreshHz: 60),
        ]

        return RawSnapshot(capturedAt: date,
                           machine: MachineInfo(model: model, chip: "Apple M4", osVersion: "27.0", hasBattery: true),
                           portNodes: r.portNodes, portControllerUUIDs: r.controllerUUIDs, usbDevices: r.usbDevices,
                           thunderboltSwitches: r.switches, battery: battery, adapter: adapter.powerSourceDetails,
                           displays: displays)
    }
}
