import BusStopCore
import SwiftUI

/// The trailing inspector: every known field of the selected host, port,
/// device or display.
struct InspectorView: View {
    var store: PortStore

    var body: some View {
        let snapshot = store.snapshot
        Group {
            switch store.selection {
            case nil:
                EmptyStateView(
                    systemName: "cursorarrow.click.2",
                    title: "Nothing selected",
                    message: "Select the Mac, a port or a device to see its details."
                )
            case .host?:
                scroll { HostInspector(store: store, snapshot: snapshot) }
            case .port(let key)?:
                if let port = snapshot.port(key) {
                    scroll { PortInspector(store: store, port: port) }
                } else {
                    missing("Port not available", "macOS no longer reports this port.")
                }
            case .device(let id)?:
                if let device = snapshot.device(id: id) {
                    scroll { DeviceInspector(store: store, device: device, port: snapshot.port(containing: id)) }
                } else {
                    missing("Device disconnected", "This device is no longer connected.")
                }
            case .display(let id)?:
                if let display = snapshot.displays.first(where: { $0.id == id }) {
                    scroll { DisplayInspector(display: display, port: display.portKey.flatMap { snapshot.port($0) }) }
                } else {
                    missing("Display disconnected", "This display is no longer connected.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { LagoonBackground(opacity: store.settings.backgroundOpacity) }
    }

    private func scroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func missing(_ title: String, _ message: String) -> some View {
        VStack(spacing: 12) {
            EmptyStateView(systemName: "questionmark.circle", title: title, message: message)
            Button("Show the Mac") { store.selection = .host }
                .buttonStyle(.link)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Host

/// The Mac as a whole: model, chip, OS, power summary and counts.
struct HostInspector: View {
    var store: PortStore
    var snapshot: HostSnapshot

    var body: some View {
        let machine = snapshot.machine
        let power = snapshot.power
        InspectorHeader(title: machine.name, subtitle: machine.chip ?? machine.model) {
            Image(systemName: machine.isLaptop ? "laptopcomputer" : "macmini")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Lagoon.accent)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Lagoon.accent.opacity(0.12)))
                .accessibilityHidden(true)
        } accessory: {
            if let reading = WindowText.hostPower(power) {
                PowerBadge(milliwatts: reading.milliwatts, direction: reading.direction, isMeasured: reading.isMeasured)
            }
        }

        InspectorSection(title: "Mac") {
            InspectorRow(label: "Name", value: machine.name, copyable: true)
            InspectorRow(label: "Model", value: machine.model, monospaced: true, copyable: true)
            InspectorRow(label: "Chip", value: machine.chip)
            InspectorRow(label: "macOS", value: machine.osVersion)
            InspectorRow(label: "Type", value: machine.isLaptop ? "Laptop" : "Desktop")
            InspectorRow(label: "Apple silicon", value: WindowText.yesNo(machine.isAppleSilicon))
        }

        InspectorSection(title: "Power") {
            InspectorRow(label: "System input", value: power.systemInputMilliwatts.map { Format.power(milliwatts: $0) })
            InspectorRow(label: "System load", value: power.systemLoadMilliwatts.map { Format.power(milliwatts: $0) })
            InspectorRow(label: "Port output", value: Format.power(milliwatts: power.portOutputMilliwatts))
            InspectorRow(label: "USB allocated", value: Format.power(milliwatts: power.usbAllocatedMilliwatts))
            InspectorRow(label: "Charger", value: power.charger?.displayName)
            InspectorRow(label: "Battery", value: power.battery?.statusText)
            InspectorRow(label: "Battery power", value: power.battery?.powerMilliwatts.map { Format.power(milliwatts: $0) })
            InspectorRow(label: "Has battery", value: WindowText.yesNo(power.hasBattery))
        }

        InspectorSection(title: "Connections") {
            InspectorRow(label: "Ports", value: "\(snapshot.ports.count)")
            InspectorRow(label: "In use", value: "\(snapshot.connectedPorts.count)")
            InspectorRow(label: "Devices", value: "\(snapshot.deviceCount)")
            InspectorRow(label: "Not tied to a port", value: "\(snapshot.otherDevices.count)")
            InspectorRow(label: "External displays", value: "\(snapshot.displays.filter { !$0.isBuiltin }.count)")
            InspectorRow(label: "Diagnostics", value: "\(snapshot.diagnostics.count)")
            InspectorRow(label: "Captured", value: InspectorFormat.capturedAt(snapshot.capturedAt))
            InspectorRow(label: "Demo data", value: WindowText.yesNo(snapshot.isDemo))
        }

        if !snapshot.captureNotes.isEmpty {
            InspectorSection(title: "Capture notes") {
                ForEach(Array(snapshot.captureNotes.enumerated()), id: \.offset) { _, note in
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(Lagoon.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Port

/// A physical port: name editor, transports, link, power, charger, cable,
/// statistics, devices and raw keys.
struct PortInspector: View {
    var store: PortStore
    var port: PhysicalPort

    var body: some View {
        InspectorHeader(title: port.label.title, subtitle: port.capabilityDescription ?? port.kind.displayName) {
            PortIcon(kind: port.kind, isActive: port.isConnected, size: 40)
        } accessory: {
            PortInspectorChips(port: port)
        }

        InspectorSection(title: "Name") {
            PortNameEditor(store: store, port: port)
            Text("Leave empty to use the default name.")
                .font(.caption)
                .foregroundStyle(Lagoon.textTertiary)
        }

        if port.liquidDetected {
            Label("Liquid detected in this port. Unplug it and let it dry.", systemImage: "drop.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Lagoon.critical)
                .padding(.horizontal, 4)
        }

        portSection
        transportSection
        if let link = port.link { LinkInspectorSection(link: link) }
        powerSection
        if let charger = port.charger { ChargerInspectorSection(charger: charger) }
        if let cable = port.cable { cableSection(cable) }
        if let statistics = port.statistics { statisticsSection(statistics) }
        devicesSection
        InspectorRawKeysSection(properties: port.properties, showRawKeys: store.settings.showRawKeys)
    }

    private var portSection: some View {
        InspectorSection(title: "Port") {
            InspectorRow(label: "Label", value: port.label.title, copyable: true)
            InspectorRow(label: "Location", value: port.label.location)
            InspectorRow(label: "Name from", value: WindowText.labelSource(port.label.source))
            InspectorRow(label: "Connector", value: port.kind.displayName)
            InspectorRow(label: "Number", value: "\(port.number)")
            InspectorRow(label: "Key", value: port.key.description, monospaced: true)
            InspectorRow(label: "Registry name", value: port.registryName, monospaced: true, copyable: true)
            InspectorRow(label: "Capability", value: port.capabilityDescription)
            InspectorRow(label: "Status", value: port.isConnected ? "Connected" : "Empty")
            InspectorRow(label: "Thunderbolt", value: WindowText.yesNo(port.supportsThunderbolt))
        }
    }

    private var transportSection: some View {
        InspectorSection(title: "Transports") {
            InspectorRow(
                label: "Supported",
                value: port.supportedTransports.isEmpty
                    ? "None reported"
                    : port.supportedTransports.sorted().map(\.displayName).joined(separator: ", ")
            )
            if port.activeTransports.isEmpty {
                InspectorRow(label: "Active", value: "None")
            } else {
                ForEach(port.activeTransports, id: \.kind) { transport in
                    InspectorRow(label: transport.kind.displayName, value: transportValue(transport))
                }
            }
        }
    }

    private func transportValue(_ transport: TransportInfo) -> String {
        var parts: [String] = [transport.link?.label ?? (transport.isActive ? "Active" : "Inactive")]
        if transport.isTunneled { parts.append("tunnelled") }
        if let product = transport.productName, !product.isEmpty { parts.append(product) }
        return parts.joined(separator: " · ")
    }

    private var powerSection: some View {
        InspectorSection(title: "Power") {
            if let power = port.power {
                InspectorRow(label: "Direction", value: WindowText.powerDirection(power.direction))
                InspectorRow(label: "Power", value: power.milliwatts.map { Format.power(milliwatts: $0) })
                InspectorRow(label: "Voltage", value: power.millivolts.map { Format.voltage(millivolts: $0) })
                InspectorRow(label: "Current", value: power.milliamps.map { Format.current(milliamps: $0) })
                InspectorRow(label: "Source", value: WindowText.powerSource(power.source))
                InspectorRow(label: "Measured", value: WindowText.yesNo(power.isMeasured))
            } else {
                InspectorRow(label: "Reading", value: "None reported")
            }
            InspectorRow(label: "Allocated to devices", value: Format.power(milliwatts: port.allocatedMilliwatts))
        }
    }

    private func cableSection(_ cable: CableInfo) -> some View {
        InspectorSection(title: "Cable") {
            InspectorRow(label: "Type", value: cable.typeDescription)
            InspectorRow(label: "Speed", value: cable.speedDescription)
            InspectorRow(label: "Active", value: cable.isActive.map { $0 ? "Yes" : "No" })
            InspectorRow(label: "Optical", value: cable.isOptical.map { $0 ? "Yes" : "No" })
            InspectorRow(label: "Rated current", value: cable.currentRatingMilliamps.map { Format.current(milliamps: $0) })
            InspectorRow(label: "Power Delivery", value: cable.pdRevision.map(InspectorFormat.pdRevision))
            InspectorRow(label: "Vendor ID", value: cable.vendorID.map(Format.hex4), monospaced: true)
            InspectorRow(label: "Product ID", value: cable.productID.map(Format.hex4), monospaced: true)
        }
    }

    private func statisticsSection(_ statistics: PortStatistics) -> some View {
        InspectorSection(title: "Statistics") {
            InspectorRow(label: "Connections", value: statistics.connectionCount.map { "\($0)" })
            InspectorRow(label: "Plug events", value: statistics.plugEventCount.map { "\($0)" })
            InspectorRow(label: "Overcurrent events", value: statistics.overcurrentCount.map { "\($0)" })
        }
    }

    private var devicesSection: some View {
        InspectorSection(title: "Devices", trailing: port.deviceCount > 0 ? "\(port.deviceCount)" : nil) {
            InspectorRow(label: "Devices", value: "\(port.deviceCount)")
            InspectorRow(label: "Allocated power", value: Format.power(milliwatts: port.allocatedMilliwatts))
            ForEach(port.devices) { device in
                InspectorLinkRow(
                    systemName: device.kind.symbolName,
                    title: device.name,
                    detail: device.link?.rateLabel
                ) {
                    store.selection = .device(device.id)
                }
            }
        }
    }
}

/// Transport chips and power badge under the port header.
struct PortInspectorChips: View {
    var port: PhysicalPort

    var body: some View {
        HStack(spacing: 6) {
            StatusRing(isActive: port.isConnected, size: 11)
            Text(port.isConnected ? "Connected" : "Empty")
                .font(Lagoon.chipFont)
                .foregroundStyle(port.isConnected ? Lagoon.accent : Lagoon.textTertiary)
            if let reading = WindowText.portPower(port) {
                PowerBadge(milliwatts: reading.milliwatts, direction: reading.direction, isMeasured: reading.isMeasured)
            }
        }
        if !port.activeTransports.isEmpty {
            HStack(spacing: 4) {
                ForEach(port.activeTransports, id: \.kind) { transport in
                    TransportChip(transport: transport)
                }
            }
        }
    }
}

/// Link generation, rate, lanes and detail.
struct LinkInspectorSection: View {
    var link: LinkInfo

    var body: some View {
        InspectorSection(title: "Link") {
            HStack {
                SpeedChip(link: link, compact: false)
                Spacer(minLength: 0)
            }
            InspectorRow(label: "Generation", value: link.generation)
            InspectorRow(label: "Rate", value: link.rateLabel)
            InspectorRow(label: "Lanes", value: InspectorFormat.lanes(link))
            InspectorRow(label: "Detail", value: link.detail)
        }
    }
}

/// The charger on a port: identity, active contract and every profile.
struct ChargerInspectorSection: View {
    var charger: ChargerInfo

    var body: some View {
        InspectorSection(title: "Charger") {
            InspectorRow(label: "Name", value: charger.displayName, copyable: true)
            InspectorRow(label: "Manufacturer", value: charger.manufacturer)
            InspectorRow(label: "Rated", value: charger.ratedWatts.map { "\($0) W" })
            InspectorRow(label: "Contract", value: contract)
            InspectorRow(label: "Contract power", value: charger.contractMilliwatts.map { Format.power(milliwatts: $0) })
            InspectorRow(label: "Family", value: charger.familyDescription)
            InspectorRow(label: "Wireless", value: WindowText.yesNo(charger.isWireless))
            InspectorRow(label: "Serial number", value: charger.serialNumber, monospaced: true, copyable: true)
            if !charger.profiles.isEmpty {
                Rectangle().fill(Lagoon.stroke).frame(height: 1)
                PowerProfilesGrid(profiles: charger.profiles)
            }
        }
    }

    private var contract: String? {
        guard let millivolts = charger.millivolts, let milliamps = charger.milliamps else {
            return charger.activeProfile?.label
        }
        return Format.contract(millivolts: millivolts, milliamps: milliamps)
    }
}

// MARK: - Device

/// A device: identity, IDs, link, power and its place in the tree.
struct DeviceInspector: View {
    var store: PortStore
    var device: DeviceNode
    var port: PhysicalPort?

    var body: some View {
        InspectorHeader(title: device.name, subtitle: subtitle) {
            DeviceIcon(kind: device.kind, size: 40)
        } accessory: {
            HStack(spacing: 6) {
                if let link = device.link { SpeedChip(link: link) }
                if let milliwatts = device.power?.allocatedMilliwatts, milliwatts > 0 {
                    PowerBadge(milliwatts: milliwatts, direction: .output, isMeasured: false)
                }
            }
        }

        identitySection
        if let link = device.link { LinkInspectorSection(link: link) }
        powerSection
        topologySection
        InspectorRawKeysSection(properties: device.properties, showRawKeys: store.settings.showRawKeys)
    }

    private var subtitle: String {
        var parts = [device.kind.displayName]
        parts.append(port?.label.title ?? "Not tied to a port")
        return parts.joined(separator: " · ")
    }

    private var identitySection: some View {
        InspectorSection(title: "Device") {
            InspectorRow(label: "Name", value: device.name, copyable: true)
            InspectorRow(label: "Kind", value: device.kind.displayName)
            InspectorRow(label: "Bus", value: WindowText.bus(device.bus))
            InspectorRow(label: "Vendor", value: device.vendorName)
            InspectorRow(label: "Vendor ID", value: device.vendorID.map(Format.hex4), monospaced: true)
            InspectorRow(label: "Product ID", value: device.productID.map(Format.hex4), monospaced: true)
            InspectorRow(label: "VID:PID", value: device.vendorProductIDString, monospaced: true, copyable: true)
            InspectorRow(label: "Serial number", value: device.serialNumber, monospaced: true, copyable: true)
            InspectorRow(label: "USB version", value: device.usbVersion)
            InspectorRow(label: "Class", value: device.deviceClass.map(InspectorFormat.usbClass))
            InspectorRow(label: "Location ID", value: device.locationID.map(Format.hex8), monospaced: true, copyable: true)
            InspectorRow(label: "Registry ID", value: device.registryID.map(InspectorFormat.registryID),
                         monospaced: true, copyable: true)
            InspectorRow(label: "Device ID", value: device.id, monospaced: true, copyable: true)
        }
    }

    private var powerSection: some View {
        InspectorSection(title: "Power") {
            if let power = device.power {
                InspectorRow(label: "Allocated", value: power.allocatedMilliwatts.map { Format.power(milliwatts: $0) })
                InspectorRow(label: "Source", value: WindowText.powerSource(power.source))
                InspectorRow(label: "Self-powered", value: power.isSelfPowered.map { $0 ? "Yes" : "No" })
            } else {
                InspectorRow(label: "Allocated", value: "Not reported")
            }
            if !device.children.isEmpty {
                InspectorRow(label: "With devices below", value: Format.power(milliwatts: device.rolledUpMilliwatts))
                InspectorRow(label: "Devices below", value: Format.power(milliwatts: device.downstreamMilliwatts))
            }
        }
    }

    private var topologySection: some View {
        InspectorSection(title: "Topology") {
            if let port {
                InspectorLinkRow(systemName: port.kind.symbolName, title: port.label.title, detail: "Port") {
                    store.selection = .port(port.key)
                }
            }
            InspectorRow(label: "Tunnelled", value: WindowText.yesNo(device.isTunneled))
            InspectorRow(label: "Chain depth", value: device.chainDepth.map { "\($0)" })
            InspectorRow(label: "Children", value: "\(device.children.count)")
            InspectorRow(label: "All devices below", value: "\(device.descendantCount)")
            ForEach(device.children) { child in
                InspectorLinkRow(systemName: child.kind.symbolName, title: child.name, detail: child.link?.rateLabel) {
                    store.selection = .device(child.id)
                }
            }
        }
    }
}

// MARK: - Display

/// An external display reported by CoreGraphics.
struct DisplayInspector: View {
    var display: DisplayInfo
    var port: PhysicalPort?

    var body: some View {
        InspectorHeader(title: display.name, subtitle: display.isBuiltin ? "Built-in display" : "External display") {
            DeviceIcon(kind: .display, size: 40)
        } accessory: {
            if let link = display.link { SpeedChip(link: link, compact: false) }
        }

        InspectorSection(title: "Display") {
            InspectorRow(label: "Name", value: display.name, copyable: true)
            InspectorRow(label: "Mode", value: display.modeDescription)
            InspectorRow(label: "Refresh rate", value: display.refreshHz.map { "\(Int($0.rounded())) Hz" })
            InspectorRow(label: "Vendor ID", value: display.vendorID.map(Format.hex4), monospaced: true)
            InspectorRow(label: "Product ID", value: display.productID.map(Format.hex4), monospaced: true)
            InspectorRow(label: "Serial number", value: display.serialNumber.map { "\($0)" }, monospaced: true, copyable: true)
            InspectorRow(label: "Built-in", value: WindowText.yesNo(display.isBuiltin))
            InspectorRow(label: "Port", value: port?.label.title ?? "Not tied to a port")
        }
        if let link = display.link { LinkInspectorSection(link: link) }
    }
}
