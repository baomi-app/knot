import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginStore: ObservableObject {
    static let shared = LaunchAtLoginStore()

    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?

    private init() {
        refresh()
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var statusText: String {
        switch status {
        case .notRegistered: "Off"
        case .enabled: "On"
        case .requiresApproval: "Needs approval in System Settings"
        case .notFound: "Unavailable for this build"
        @unknown default: "Unknown"
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
