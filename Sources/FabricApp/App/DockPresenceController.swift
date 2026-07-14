import AppKit

/// Keeps Fabric discoverable in the Dock while its management window is open,
/// then restores menu-bar-only behavior after that window closes.
@MainActor
enum DockPresenceController {
    static func managementWindowDidOpen() {
        guard NSApplication.shared.activationPolicy() != .regular else { return }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func managementWindowDidClose() {
        guard NSApplication.shared.activationPolicy() != .accessory else { return }

        NSApplication.shared.setActivationPolicy(.accessory)
    }

    static func closeManagementWindow() {
        let managementWindow = NSApplication.shared.windows.first {
            $0.title == "Exnano Fabric"
        }
        managementWindow?.performClose(nil)
    }
}
