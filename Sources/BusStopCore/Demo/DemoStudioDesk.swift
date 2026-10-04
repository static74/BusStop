import Foundation

/// MacBook Pro 14-inch (M5 Pro) at a desk.
///
/// - MagSafe: Apple 140W USB-C Power Adapter on a 28 V × 5 A contract,
///   about 62 W flowing in.
/// - Left Center USB-C (port 1): Studio Display XDR over Thunderbolt 5 at
///   80 Gb/s (two lanes at 40 Gb/s). The display's USB hub has a Samsung T9
///   on its downstream port at 10 Gb/s and the display's camera at USB 2.
/// - Left Front USB-C (port 2): a bus-powered USB-C hub (VIA Labs VL822,
///   a USB 3 hub plus its USB 2 companion) with a keyboard, a mouse and a
///   USB 3 flash drive that fell back to USB 2. The SMC measures about 4 W
///   out of this port.
/// - Right Center USB-C (port 3) and the HDMI port: empty.
enum DemoStudioDesk {
    static let model = "Mac17,9"
    static let soc = "T6050"

    /// Thunderbolt UID of the display's switch.
    static let displayUID: Int64 = 0x05AC_2B44_8D10_0F01

    static func raw(at date: Date, tick: Int) -> RawSnapshot {
        let wave = DemoWave(tick: tick)
        var r = DemoRegistry()
        let uuids = (magSafe: DemoPower.uuid(seed: 0x5D_0011), port1: DemoPower.uuid(seed: 0x5D_0021),
                     port2: DemoPower.uuid(seed: 0x5D_0022), port3: DemoPower.uuid(seed: 0x5D_0023))

        // Power: about 62 W in at 28 V; the hub port draws about 4 W.
        let inputVolts = wave.value(27.94, amplitude: 0.003, phase: 0.4)
        let inputWatts = wave.value(62.0, amplitude: 0.03, phase: 0)
        let hubVolts = wave.value(5.08, amplitude: 0.002, phase: 2.9)
        let hubWatts = wave.value(3.95, amplitude: 0.035, phase: 2.2)
        let flow = DemoPowerFlow(systemPowerIn: DemoPower.milliwatts(inputWatts * 1000),
                                 systemVoltageIn: DemoPower.milliwatts(inputVolts * 1000),
                                 systemLoad: DemoPower.milliwatts(wave.value(38_400, amplitude: 0.04, phase: 1.3)))

        // MagSafe 3 with the 140 W adapter.
        let adapter = DemoAdapter.apple140W
        let magSafe = r.hpmPort(number: 1, type: PortKey.magSafeType, typeDescription: "MagSafe 3",
                                className: "AppleHPMInterfaceType11", uuid: uuids.magSafe,
                                state: DemoPortState(supported: ["CC"], active: ["CC"], features: ["LDCM", "Power In"],
                                                     plugEvents: 412))
        let magSafePartner = r.partner(on: magSafe)
        r.appleCharger(on: magSafe, sop: magSafePartner, name: adapter.name, model: adapter.model,
                       serial: adapter.serial)
        r.powerIn(on: magSafe, sources: [
            ("USB-PD", adapter.powerSourceOptions(uuidSeed: 0x5D_1000)),
            ("Brick ID", [DemoRegistry.powerOption(millivolts: 5_000, milliamps: 1_500,
                                                   uuid: DemoPower.uuid(seed: 0x5D_1100))]),
        ], winner: "USB-PD")

        // Port 1: Studio Display XDR over Thunderbolt 5.
        let port1 = r.hpmPort(number: 1, uuid: uuids.port1,
                              state: DemoPortState(supported: ["CC", "USB2", "USB3", "DisplayPort", "CIO"],
                                                   active: ["CC", "CIO", "USB2"], plugEvents: 37, orientation: 2))
        r.partner(on: port1)
        r.cableMarker(on: port1, typeDescription: "Passive Cable", vdos: [
            DemoCableVDO.passiveHeader(vendorID: 0x05AC), 0,
            DemoCableVDO.product(productID: 0x7322), DemoCableVDO.passiveCable(speed: 4, fiveAmps: true, latency: 1),
        ])
        let cio = r.transport("CIO", on: port1, parent: port1.id, active: true, extra: [
            "AsymmetricModeSupported": true,
            "TunneledTransportsActive": ["USB3", "DisplayPort"],
            "CableTypeDescription": "Passive",
        ])
        let tunnelledUSB3 = r.transport("USB3", on: port1, parent: cio, active: true, tunneled: true,
                                        extra: DemoRegistry.usb3Keys(generation: 2))
        r.transport("DisplayPort", on: port1, parent: cio, active: true, tunneled: true,
                    extra: DemoRegistry.displayPortKeys(rate: "UHBR13.5", rateCode: 6, lanes: 4,
                                                        product: "Studio Display XDR", manufacturer: "Apple Inc."))
        let port1USB2 = r.transport("USB2", on: port1, parent: port1.id, active: true,
                                    extra: DemoRegistry.usb2Keys(product: "Studio Display XDR Hub",
                                                                 manufacturer: "Apple Inc.", vendorID: 0x05AC,
                                                                 productID: 0x1117, deviceClass: 9))

        // Port 2: the USB-C hub.
        let port2 = r.hpmPort(number: 2, uuid: uuids.port2,
                              state: DemoPortState(supported: ["CC", "USB2", "USB3", "DisplayPort", "CIO"],
                                                   active: ["CC", "USB3", "USB2"], plugEvents: 58))
        let port2USB3 = r.transport("USB3", on: port2, parent: port2.id, active: true,
                                    extra: DemoRegistry.usb3Keys(generation: 2))
        let port2USB2 = r.transport("USB2", on: port2, parent: port2.id, active: true,
                                    extra: DemoRegistry.usb2Keys(product: "USB2.1 Hub", manufacturer: "VIA Labs, Inc.",
                                                                 vendorID: 0x2109, productID: 0x2822, deviceClass: 9))

        // Port 3 (right side) and HDMI: nothing plugged in.
        r.hpmPort(number: 3, uuid: uuids.port3,
                  state: DemoPortState(supported: ["CC", "USB2", "USB3", "DisplayPort", "CIO"], plugEvents: 21))
        r.hdmiPort(hotPlug: false)

        // USB devices on port 1, through the display.
        let drd0 = r.nativeController(drd: 0, soc: soc, port: port1, hpm: 0)
        let displayHub = r.usbRoot(DemoUSBDevice(
            name: "Studio Display XDR Hub", vendorName: "Apple Inc.", vendorID: 0x05AC, productID: 0x1116,
            bcdDevice: 0x0210, bcdUSB: 0x0320, deviceClass: 9, speed: LinkDecoding.superSpeedPlus,
            hubPowerSupply: 900, isTunneled: true), on: drd0, transport: tunnelledUSB3)
        let displayHub2 = r.usbRoot(DemoUSBDevice(
            name: "Studio Display XDR Hub", vendorName: "Apple Inc.", vendorID: 0x05AC, productID: 0x1117,
            bcdDevice: 0x0210, bcdUSB: 0x0210, deviceClass: 9, speed: LinkDecoding.highSpeed,
            hubPowerSupply: 500), on: drd0, transport: port1USB2)
        r.usbChild(DemoUSBDevice(
            name: "PSSD T9", vendorName: "Samsung", vendorID: 0x04E8, productID: 0x4011, bcdDevice: 0x0100,
            bcdUSB: 0x0320, speed: LinkDecoding.superSpeedPlus, allocation: 896, serial: "S7MPNS0X104823L",
            interfaces: [RawUSBInterface(interfaceClass: 8, interfaceSubClass: 6, interfaceProtocol: 0x62)]),
            of: displayHub, hubPort: 1)
        r.usbChild(DemoUSBDevice(
            name: "Studio Display XDR Camera", vendorName: "Apple Inc.", vendorID: 0x05AC, productID: 0x1118,
            bcdDevice: 0x0120, bcdUSB: 0x0200, speed: LinkDecoding.highSpeed, allocation: 500,
            serial: "0000S2DX7C1A",
            interfaces: [RawUSBInterface(interfaceClass: 14, interfaceSubClass: 1, interfaceProtocol: 0),
                         RawUSBInterface(interfaceClass: 14, interfaceSubClass: 2, interfaceProtocol: 0),
                         RawUSBInterface(interfaceClass: 1, interfaceSubClass: 1, interfaceProtocol: 0),
                         RawUSBInterface(interfaceClass: 1, interfaceSubClass: 2, interfaceProtocol: 0)]),
            of: displayHub2, hubPort: 2)

        // USB devices on port 2, behind the hub.
        let drd1 = r.nativeController(drd: 1, soc: soc, port: port2, hpm: 1)
        r.usbRoot(DemoUSBDevice(
            name: "USB3.1 Hub", vendorName: "VIA Labs, Inc.", vendorID: 0x2109, productID: 0x0822, bcdDevice: 0x9223,
            bcdUSB: 0x0320, deviceClass: 9, speed: LinkDecoding.superSpeedPlus, hubPowerSupply: 0),
            on: drd1, transport: port2USB3)
        let usb2Hub = r.usbRoot(DemoUSBDevice(
            name: "USB2.1 Hub", vendorName: "VIA Labs, Inc.", vendorID: 0x2109, productID: 0x2822, bcdDevice: 0x9223,
            bcdUSB: 0x0210, deviceClass: 9, speed: LinkDecoding.highSpeed, allocation: 100, hubPowerSupply: 0),
            on: drd1, transport: port2USB2)
        r.usbChild(DemoUSBDevice(
            name: "Keychron K8 Pro", vendorName: "Keychron", vendorID: 0x3434, productID: 0x0280, bcdDevice: 0x0100,
            bcdUSB: 0x0200, speed: LinkDecoding.fullSpeed, allocation: 100,
            interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1, interfaceProtocol: 1),
                         RawUSBInterface(interfaceClass: 3, interfaceSubClass: 0, interfaceProtocol: 0)]),
            of: usb2Hub, hubPort: 1)
        r.usbChild(DemoUSBDevice(
            name: "USB Optical Mouse", vendorName: "Logitech", vendorID: 0x046D, productID: 0xC077, bcdDevice: 0x7200,
            bcdUSB: 0x0200, speed: LinkDecoding.lowSpeed, allocation: 100,
            interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1, interfaceProtocol: 2)]),
            of: usb2Hub, hubPort: 2)
        r.usbChild(DemoUSBDevice(
            name: "DataTraveler 3.0", vendorName: "Kingston", vendorID: 0x0951, productID: 0x1666, bcdDevice: 0x0110,
            bcdUSB: 0x0300, speed: LinkDecoding.highSpeed, allocation: 500, serial: "E0D55EA574A3F4C0B8640134",
            interfaces: [RawUSBInterface(interfaceClass: 8, interfaceSubClass: 6, interfaceProtocol: 0x50)]),
            of: usb2Hub, hubPort: 4)

        // Thunderbolt: one host switch per USB-C port, the display on port 1.
        let host1 = r.hostSwitch(acio: 0, socket: 1, uid: 0x05AC_7A31_C0DE_0001, modelName: "MacBook Pro",
                                 link: .tb5, adapters: [
                                     DemoThunderboltAdapter(portNumber: 5, description: "PCIe Adapter", isLive: false),
                                     DemoThunderboltAdapter(portNumber: 7, description: "USB Gen T Adapter", isLive: true),
                                     DemoThunderboltAdapter(portNumber: 9, description: "DP or HDMI Adapter", isLive: true),
                                     DemoThunderboltAdapter(portNumber: 10, description: "DP or HDMI Adapter",
                                                            isLive: false),
                                 ])
        r.hostSwitch(acio: 1, socket: 2, uid: 0x05AC_7A31_C0DE_0002, modelName: "MacBook Pro", link: nil)
        r.hostSwitch(acio: 2, socket: 3, uid: 0x05AC_7A31_C0DE_0003, modelName: "MacBook Pro", link: nil)
        r.deviceSwitch(below: host1, parentLane: 1, depth: 1, uid: displayUID, className: "IOThunderboltSwitchType7",
                       vendorID: 1452, vendorName: "Apple Inc.", deviceID: 0x1116, modelName: "Studio Display XDR",
                       link: .tb5, adapters: [
                           DemoThunderboltAdapter(portNumber: 8, description: "PCIe Adapter", isLive: false),
                           DemoThunderboltAdapter(portNumber: 10, description: "DP or HDMI Adapter", isLive: true),
                           DemoThunderboltAdapter(portNumber: 12, description: "USB Gen T Adapter", isLive: true),
                       ])

        // SMC: D1–D3 are the USB-C controllers, D4 is MagSafe.
        let smc = [
            DemoPower.channel(1, uuid: uuids.port1, volts: 5.02, amps: 0),
            DemoPower.channel(2, uuid: uuids.port2, volts: hubVolts, amps: hubWatts / hubVolts,
                              contractMilliwatts: 15_000),
            DemoPower.channel(3, uuid: uuids.port3, volts: 0, amps: 0),
            DemoPower.channel(4, uuid: uuids.magSafe, volts: inputVolts, amps: inputWatts / inputVolts,
                              contractMilliwatts: 140_000),
        ]

        let battery = DemoPower.laptopBattery(
            percent: 76, charging: true, adapter: adapter, flow: flow, voltage: 12_634, cycleCount: 63,
            minutesRemaining: 41,
            // Updated less often than the SMC: the hub port's last report.
            powerOut: [DemoPower.powerOut(port: 2, milliwatts: 3_912, millivolts: 5_080)])

        let displays = [
            RawDisplay(id: 1, name: "Built-in Liquid Retina XDR Display", vendorID: 0x610, productID: 0xA052,
                       isBuiltin: true, pixelWidth: 3024, pixelHeight: 1964, refreshHz: 120),
            RawDisplay(id: 3, name: "Studio Display XDR", vendorID: 0x610, productID: 0xAE3A, serialNumber: 0x2C41_09F3,
                       isBuiltin: false, isMain: true, pixelWidth: 5120, pixelHeight: 2880, refreshHz: 120),
        ]

        return RawSnapshot(capturedAt: date,
                           machine: MachineInfo(model: model, chip: "Apple M5 Pro", osVersion: "27.0", hasBattery: true),
                           portNodes: r.portNodes, portControllerUUIDs: r.controllerUUIDs, usbDevices: r.usbDevices,
                           thunderboltSwitches: r.switches, battery: battery, adapter: adapter.powerSourceDetails,
                           smcChannels: smc, displays: displays)
    }
}
