import Foundation
import Observation
import ServiceManagement

/// Manages launch at login and approval status.
@MainActor
@Observable
final class LaunchAtLoginManager {
    /// Whether launch at login is enabled or awaiting approval.
    private(set) var isEnabled = false
    /// Whether launch at login needs system approval.
    private(set) var needsApproval = false
    /// The latest error to show to the user.
    var errorMessage: String?

    /// Loads the current launch at login status.
    init() {
        refresh()
    }

    /// Reloads launch at login and approval status.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    /// Updates launch at login registration and refreshes its status.
    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled,
                   SMAppService.mainApp.status != .requiresApproval
                {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// Opens Login Items in System Settings.
    func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
