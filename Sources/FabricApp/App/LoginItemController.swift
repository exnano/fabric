import ServiceManagement
import SwiftUI

/// Manages Fabric's user login-item registration through Apple's ServiceManagement API.
/// This API updates System Settings > General > Login Items without editing launchd files.
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var isUpdating = false
    @Published var errorMessage: String?

    private let service = SMAppService.mainApp

    init() {
        refreshStatus()
    }

    func setEnabled(_ shouldEnable: Bool) {
        guard !isUpdating else { return }

        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }

        do {
            if shouldEnable {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refreshStatus()
    }

    func refreshStatus() {
        switch service.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
        case .requiresApproval:
            isEnabled = true
            requiresApproval = true
        case .notRegistered, .notFound:
            isEnabled = false
            requiresApproval = false
        @unknown default:
            isEnabled = false
            requiresApproval = false
        }
    }
}
