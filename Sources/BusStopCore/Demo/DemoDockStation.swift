import Foundation

/// Mac mini (M4 Pro) on a desk with a Thunderbolt 5 dock.
///
/// - Rear (left) USB-C (port 3): a CalDigit TS5 Plus-style dock over
///   Thunderbolt 5 at 80 Gb/s. Its USB hub carries a 2.5 GbE Ethernet
///   adapter, a SanDisk SSD at 10 Gb/s, a USB audio interface and an SD card
///   reader; a second SanDisk SSD runs at 20 Gb/s on the dock's own PCIe USB
///   controller. The SMC measures about 1 W going to the dock.
/// - Front (left) USB-C (port 1, a bare `IOPort` without a port
///   controller): a Samsung T7 Shield at 10 Gb/s.
/// - HDMI: an LG UltraFine 4K display at 3840 × 2160, 60 Hz.
/// - No battery and no power telemetry, as on a real Mac mini.
///
/// Port numbers follow the port-location catalogue: front ports 1 and 2,
/// rear Thunderbolt ports 3 to 5 (`Socket ID` 3 to 5).
enum DemoDockStation {
    static let model = "Mac16,11"
    static let soc = "T6041"

    /// Thunderbolt UID of the dock's switch.
    static let dockUID: Int64 = 0x003D_5A11_77C2_0501

    static func raw(at date: Date, tick: Int) -> RawSnapshot {
        let wave = DemoWave(tick: tick)
        var r = DemoRegistry()
        let uuids = (port3: DemoPower.uuid(seed: 0xD0_0023), port4: DemoPower.uuid(seed: 0xD0_0024),
                     port5: DemoPower.uuid(seed: 0xD0_0025))
        let dockVolts = wave.value(5.04, amplitude: 0.002, phase: 0.5)
        let dockWatts = wave.value(1.15, amplitude: 0.04, phase: 1.9)

        // Front ports: bare IOPorts on the SoC's own controllers.
        let front1 = r.barePort(number: 1, supported: ["USB2", "USB3"], active: ["USB3"])
        let front1USB3 = r.transport("USB3", on: front1, parent: front1.id, active: true,
                                     extra: DemoRegistry.usb3Keys(generation: 2))
        r.transport("USB2", on: front1, parent: front1.id, active: false)
        r.barePort(number: 2, supported: ["USB2", "USB3"], active: [])

        // Rear Thunderbolt 5 ports; the dock is on port 3.
        let thunderboltPort = ["CC", "USB2", "USB3", "DisplayPort", "CIO"]
        let port3 = r.hpmPort(number: 3, uuid: uuids.port3,
                              state: DemoPortState(supported: thunderboltPort, active: ["CC", "CIO", "USB2"],
                                                   plugEvents: 12))
        r.partner(on: port3)
        r.cableMarker(on: port3, typeDescription: "Passive Cable", vdos: [
            DemoCableVDO.passiveHeader(vendorID: 0x2188), 0,
            DemoCableVDO.product(productID: 0x0805), DemoCableVDO.passiveCable(speed: 4, fiveAmps: true, latency: 1),
        ])
        let cio = r.transport("CIO", on: port3, parent: port3.id, active: true, extra: [
            "AsymmetricModeSupported": true,
            "TunneledTransportsActive": ["USB3"],
            "CableTypeDescription": "Passive",
        ])
        let tunnelledUSB3 = r.transport("USB3", on: port3, parent: cio, active: true, tunneled: true,
                                        extra: DemoRegistry.usb3Keys(generation: 2))
        let port3USB2 = r.transport("USB2", on: port3, parent: port3.id, active: true,
                                    extra: DemoRegistry.usb2Keys(product: "TS5 Plus Hub", manufacturer: "CalDigit, Inc.",
                                                                 vendorID: 0x2188, productID: 0x5501, deviceClass: 9))
        r.hpmPort(number: 4, uuid: uuids.port4, state: DemoPortState(supported: thunderboltPort, plugEvents: 3))
        r.hpmPort(number: 5, uuid: uuids.port5, state: DemoPortState(supported: thunderboltPort, plugEvents: 0))
        r.hdmiPort(hotPlug: true)

        // The front SSD.
        let frontController = r.nativeController(drd: 3, soc: soc, port: front1, hpm: nil)
        r.usbRoot(DemoUSBDevice(
            name: "PSSD T7 Shield", vendorName: "Samsung", vendorID: 0x04E8, productID: 0x61FB, bcdDevice: 0x0100,
            bcdUSB: 0x0320, speed: LinkDecoding.superSpeedPlus, allocation: 896, serial: "S6NPNS0W512893K",
            interfaces: [RawUSBInterface(interfaceClass: 8, interfaceSubClass: 6, interfaceProtocol: 0x62)]),
            on: frontController, transport: front1USB3)

        // The dock's USB hub: SuperSpeed half through the USB4 tunnel,
        // USB 2 half on the cable's own USB 2 pair.
        let drd0 = r.nativeController(drd: 0, soc: soc, port: port3, hpm: 0)
        let dockHub = r.usbRoot(DemoUSBDevice(
            name: "TS5 Plus Hub", vendorName: "CalDigit, Inc.", vendorID: 0x2188, productID: 0x5500, bcdDevice: 0x0100,
            bcdUSB: 0x0320, deviceClass: 9, speed: LinkDecoding.superSpeedPlus, hubPowerSupply: 3_000,
            isTunneled: true), on: drd0, transport: tunnelledUSB3)
        let dockHub2 = r.usbRoot(DemoUSBDevice(
            name: "TS5 Plus Hub", vendorName: "CalDigit, Inc.", vendorID: 0x2188, productID: 0x5501, bcdDevice: 0x0100,
            bcdUSB: 0x0210, deviceClass: 9, speed: LinkDecoding.highSpeed, hubPowerSupply: 3_000),
            on: drd0, transport: port3USB2)
        r.usbChild(DemoUSBDevice(
            name: "USB 10/100/1G/2.5G LAN", vendorName: "Realtek", vendorID: 0x0BDA, productID: 0x8156,
            bcdDevice: 0x3104, bcdUSB: 0x0320, speed: LinkDecoding.superSpeed, allocation: 288, serial: "401000001",
            interfaces: [RawUSBInterface(interfaceClass: 2, interfaceSubClass: 13, interfaceProtocol: 0),
                         RawUSBInterface(interfaceClass: 10, interfaceSubClass: 0, interfaceProtocol: 1)]),
            of: dockHub, hubPort: 1)
        r.usbChild(DemoUSBDevice(
            name: "Extreme 55AE", vendorName: "SanDisk", vendorID: 0x0781, productID: 0x55AE, bcdDevice: 0x1012,
            bcdUSB: 0x0320, speed: LinkDecoding.superSpeedPlus, allocation: 896, serial: "32343133464E343031383537",
            interfaces: [RawUSBInterface(interfaceClass: 8, interfaceSubClass: 6, interfaceProtocol: 0x62)]),
            of: dockHub, hubPort: 2)
        r.usbChild(DemoUSBDevice(
            name: "Scarlett 2i2 4th Gen", vendorName: "Focusrite", vendorID: 0x1235, productID: 0x8219,
            bcdDevice: 0x0216, bcdUSB: 0x0200, speed: LinkDecoding.highSpeed, allocation: 500, serial: "S2YQ8F5402A1C7",
            interfaces: [RawUSBInterface(interfaceClass: 1, interfaceSubClass: 1, interfaceProtocol: 0x20),
                         RawUSBInterface(interfaceClass: 1, interfaceSubClass: 2, interfaceProtocol: 0x20),
                         RawUSBInterface(interfaceClass: 1, interfaceSubClass: 2, interfaceProtocol: 0x20),
                         RawUSBInterface(interfaceClass: 0xFE, interfaceSubClass: 1, interfaceProtocol: 1)]),
            of: dockHub2, hubPort: 3)
        r.usbChild(DemoUSBDevice(
            name: "SD Card Reader", vendorName: "Genesys Logic", vendorID: 0x05E3, productID: 0x0751,
            bcdDevice: 0x1414, bcdUSB: 0x0200, speed: LinkDecoding.highSpeed, allocation: 500, serial: "000000001414",
            interfaces: [RawUSBInterface(interfaceClass: 8, interfaceSubClass: 6, interfaceProtocol: 0x50)]),
            of: dockHub2, hubPort: 4)

        // The 20 Gb/s SSD on the dock's PCIe USB controller.
        let dockController = r.pcieController(className: "AppleASMediaUSBXHCI", soc: soc, bus: 5, pcie: 0)
        r.usbRoot(DemoUSBDevice(
            name: "Extreme Pro 55AF", vendorName: "SanDisk", vendorID: 0x0781, productID: 0x55AF, bcdDevice: 0x1012,
            bcdUSB: 0x0320, speed: LinkDecoding.superSpeedPlus2x2, allocation: 896,
            serial: "32333137343031343832313939",
            interfaces: [RawUSBInterface(interfaceClass: 8, interfaceSubClass: 6, interfaceProtocol: 0x62)]),
            on: dockController, transport: nil)

        // Thunderbolt: one host switch per rear port, the dock on port 3.
        let host3 = r.hostSwitch(acio: 0, socket: 3, uid: 0x05AC_3C66_B2E0_0003, modelName: "Mac mini",
                                 link: .tb5, adapters: [
                                     DemoThunderboltAdapter(portNumber: 5, description: "PCIe Adapter", isLive: true),
                                     DemoThunderboltAdapter(portNumber: 7, description: "USB Gen T Adapter", isLive: true),
                                     DemoThunderboltAdapter(portNumber: 9, description: "DP or HDMI Adapter",
                                                            isLive: false),
                                     DemoThunderboltAdapter(portNumber: 10, description: "DP or HDMI Adapter",
                                                            isLive: false),
                                 ])
        r.hostSwitch(acio: 1, socket: 4, uid: 0x05AC_3C66_B2E0_0004, modelName: "Mac mini", link: nil)
        r.hostSwitch(acio: 2, socket: 5, uid: 0x05AC_3C66_B2E0_0005, modelName: "Mac mini", link: nil)
        r.deviceSwitch(below: host3, parentLane: 1, depth: 1, uid: dockUID,
                       className: "IOThunderboltSwitchIntelJHL9580", vendorID: 0x3D, vendorName: "CalDigit, Inc.",
                       deviceID: 0x0051, modelName: "TS5 Plus", link: .tb5, downstreamLanes: [3, 4],
                       adapters: [
                           DemoThunderboltAdapter(portNumber: 8, description: "PCIe Adapter", isLive: true),
                           DemoThunderboltAdapter(portNumber: 10, description: "DP or HDMI Adapter", isLive: false),
                           DemoThunderboltAdapter(portNumber: 11, description: "DP or HDMI Adapter", isLive: false),
                           DemoThunderboltAdapter(portNumber: 12, description: "USB Gen T Adapter", isLive: true),
                       ])

        // SMC: one channel per rear port controller; desktops publish no contract keys.
        let smc = [
            DemoPower.channel(1, uuid: uuids.port3, volts: dockVolts, amps: dockWatts / dockVolts),
            DemoPower.channel(2, uuid: uuids.port4, volts: 0, amps: 0),
            DemoPower.channel(3, uuid: uuids.port5, volts: 0, amps: 0),
        ]

        let displays = [
            RawDisplay(id: 2, name: "LG UltraFine", vendorID: 0x1E6D, productID: 0x5B71, serialNumber: 0x0003_1F2C,
                       isBuiltin: false, isMain: true, pixelWidth: 3840, pixelHeight: 2160, refreshHz: 60),
        ]

        return RawSnapshot(capturedAt: date,
                           machine: MachineInfo(model: model, chip: "Apple M4 Pro", osVersion: "27.0", hasBattery: false),
                           portNodes: r.portNodes, portControllerUUIDs: r.controllerUUIDs, usbDevices: r.usbDevices,
                           thunderboltSwitches: r.switches, battery: DemoPower.desktopBattery(), smcChannels: smc,
                           displays: displays)
    }
}
