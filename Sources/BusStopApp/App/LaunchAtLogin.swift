import Foundation
import ServiceManagement

/// Launch-at-login through `SMAppService.mainApp`.
///
/// Ad-hoc signed builds sometimes get "Operation not permitted"; callers show
/// `statusDescription` and offer `openSystemSettings()` as a fallback.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Bus Stop opens when you log in."
        case .requiresApproval: return "Waiting for approval in System Settings › General › Login Items."
        case .notRegistered: return "Bus Stop does not open at login."
        case .notFound: return "Login item unavailable. Move Bus Stop to /Applications and try again."
        @unknown default: return "Login item status unknown."
        }
    }

    /// Registers or unregisters. Throws the ServiceManagement error on failure.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
