import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isRegistered = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            isRegistered = true
            requiresApproval = false
        case .requiresApproval:
            isEnabled = false
            isRegistered = true
            requiresApproval = true
        case .notRegistered, .notFound:
            isEnabled = false
            isRegistered = false
            requiresApproval = false
        @unknown default:
            isEnabled = false
            isRegistered = false
            requiresApproval = false
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> String? {
        errorMessage = nil
        let service = SMAppService.mainApp

        do {
            if enabled {
                switch service.status {
                case .enabled:
                    break
                case .requiresApproval:
                    break
                case .notRegistered, .notFound:
                    try service.register()
                @unknown default:
                    try service.register()
                }
            } else {
                switch service.status {
                case .enabled, .requiresApproval:
                    try service.unregister()
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    try service.unregister()
                }
            }
        } catch {
            refreshStatus()
            let message = L10n.text(enabled
                ? "launch_at_login.enable_failed"
                : "launch_at_login.disable_failed")
            errorMessage = message
            return message
        }

        refreshStatus()
        if enabled, requiresApproval {
            openApprovalSettings()
        }
        return nil
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
