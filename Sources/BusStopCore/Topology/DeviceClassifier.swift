import Foundation

/// Decides what kind of device a USB device is, for icons and grouping.
///
/// Evidence is taken in order of reliability: the device class and the
/// interface classes it declares, then keywords in its name, then known Apple
/// product names. Keywords match whole words so that "Microsoft" never
/// counts as "mic" and "Atlantic" never counts as "lan".
enum DeviceClassifier {
    static let appleVendorID = 0x05AC

    /// USB class codes used here.
    enum USBClass {
        static let audio = 1
        static let cdc = 2
        static let hid = 3
        static let image = 6
        static let printer = 7
        static let massStorage = 8
        static let hub = 9
        static let cdcData = 10
        static let video = 14
        static let wireless = 0xE0
    }

    /// Classifies one USB device.
    static func classify(deviceClass: Int?, interfaces: [RawUSBInterface], name: String,
                         vendorID: Int?) -> DeviceKind {
        let words = TopologyText.words(name)
        let isApple = vendorID == appleVendorID
        var classes = Set(interfaces.map(\.interfaceClass))
        if let deviceClass, deviceClass != 0, deviceClass != 0xEF, deviceClass != 0xFF {
            classes.insert(deviceClass)
        }

        // Apple phones and tablets declare PTP (image), CDC and vendor
        // interfaces; their name settles which.
        if isApple || classes.contains(USBClass.image) {
            if has(words, "iphone") { return .phone }
            if has(words, "ipad") { return .tablet }
        }
        if classes.contains(USBClass.hub) { return .hub }
        if classes.contains(USBClass.video) { return .camera }
        if classes.contains(USBClass.massStorage) { return .storage }

        let hidProtocols = Set(interfaces.filter { $0.interfaceClass == USBClass.hid }.compactMap(\.interfaceProtocol))
        if hidProtocols.contains(1) { return .keyboard }
        if hidProtocols.contains(2) { return .mouse }

        // CDC communication interfaces with the ECM, EEM or NCM subclass are
        // Ethernet adapters; their data travels on a class 10 interface.
        let networkSubclasses: Set<Int> = [6, 12, 13]
        if interfaces.contains(where: {
            $0.interfaceClass == USBClass.cdc && networkSubclasses.contains($0.interfaceSubClass ?? -1)
        }) {
            return .network
        }
        if classes.contains(USBClass.audio) { return .audio }
        if classes.contains(USBClass.image) { return .camera }
        if classes.contains(USBClass.printer) { return .printer }
        if classes.contains(USBClass.wireless) { return .wireless }

        if let kind = kindFromName(words) { return kind }
        if isApple, let kind = appleKind(words) { return kind }
        if classes.contains(USBClass.hid) { return .input }
        return .other
    }

    /// Keyword rules on a device name.
    static func kindFromName(_ words: [String]) -> DeviceKind? {
        if has(words, "hub") { return .hub }
        if has(words, "dock", "docking") { return .dock }
        if has(words, "display", "monitor") { return .display }
        if has(words, "ssd", "drive", "disk", "flash", "storage") || hasPhrase(words, "card", "reader") { return .storage }
        if has(words, "keyboard") { return .keyboard }
        if has(words, "mouse", "trackpad", "trackball") { return .mouse }
        if has(words, "ethernet", "lan", "network", "gigabit") { return .network }
        if has(words, "audio", "dac", "headset", "headphones", "speaker", "speakers", "mic", "microphone") { return .audio }
        if has(words, "camera", "webcam", "facetime") { return .camera }
        if has(words, "iphone") { return .phone }
        if has(words, "ipad") { return .tablet }
        if has(words, "adapter", "dongle") { return .adapter }
        return nil
    }

    /// Apple product names that the keyword rules miss.
    static func appleKind(_ words: [String]) -> DeviceKind? {
        if has(words, "airpods", "beats", "earpods") { return .audio }
        if has(words, "superdrive") { return .storage }
        if has(words, "magic") { return .input }
        if has(words, "watch") { return .other }
        return nil
    }

    /// Kind of a hub after its children are known: a hub named like a dock
    /// with an Ethernet adapter or a display below it is a dock.
    static func refineHub(_ node: DeviceNode) -> DeviceKind {
        guard node.kind == .hub else { return node.kind }
        let words = TopologyText.words(node.name)
        guard has(words, "dock", "docking", "station") else { return node.kind }
        let below = node.flattened().dropFirst().map(\.device.kind)
        return below.contains(.network) || below.contains(.display) ? .dock : node.kind
    }

    static func has(_ words: [String], _ keywords: String...) -> Bool {
        words.contains { keywords.contains($0) }
    }

    static func hasPhrase(_ words: [String], _ first: String, _ second: String) -> Bool {
        guard words.count >= 2 else { return false }
        for i in 0..<(words.count - 1) where words[i] == first && words[i + 1] == second { return true }
        return false
    }
}
