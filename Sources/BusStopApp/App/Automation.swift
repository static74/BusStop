import AppKit
import Foundation

/// Opens a view by itself after launch so CI can take screenshots of the real
/// app without UI scripting. Driven by the `BUSSTOP_AUTOMATION` environment
/// variable; does nothing when it is unset.
///
/// Values: `popover`, `topology`, `settings`, `settings:<tab>` (a
/// `SettingsTab` raw value), `about`. Combine with the launch arguments
/// `-demoMode YES -demoScenario studioDesk` to show demo data without
/// changing saved preferences.
enum Automation {
    static let environmentKey = "BUSSTOP_AUTOMATION"

    static var request: String? {
        let value = ProcessInfo.processInfo.environment[environmentKey]?.trimmingCharacters(in: .whitespaces)
        return value?.isEmpty == false ? value : nil
    }

    /// Performs the requested action after `delay`, giving the first capture
    /// time to land.
    static func run(statusItemController: StatusItemController?, delay: TimeInterval = 2.5) {
        guard let request else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                perform(request, statusItemController: statusItemController)
            }
        }
    }

    private static func perform(_ request: String, statusItemController: StatusItemController?) {
        let parts = request.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "popover":
            statusItemController?.showPopover()
        case "topology":
            WindowManager.shared.showTopology()
        case "settings":
            let tab = parts.count > 1 ? SettingsTab(rawValue: parts[1]) : nil
            WindowManager.shared.showSettings(tab: tab)
        case "about":
            WindowManager.shared.showAbout()
        default:
            FileHandle.standardError.write(Data("Unknown \(environmentKey) value: \(request)\n".utf8))
        }
    }
}
