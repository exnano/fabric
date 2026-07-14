import AppKit
import SwiftUI

@main
@MainActor
struct FabricApp: App {
    @NSApplicationDelegateAdaptor(FabricApplicationDelegate.self)
    private var applicationDelegate

    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        model.startMonitoring()
    }

    var body: some Scene {
        MenuBarExtra("Fabric", systemImage: "server.rack") {
            MenuBarContentView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("Exnano Fabric", id: "management") {
            ServiceListView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 940, height: 640)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Close Fabric Window") {
                    DockPresenceController.closeManagementWindow()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

@MainActor
final class FabricApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationIconController.updateForCurrentAppearance()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceDidChange),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        // Fabric starts as an LSUIElement app. Activating here brings the initial
        // management window forward; its appearance then controls Dock visibility.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func systemAppearanceDidChange(_ notification: Notification) {
        ApplicationIconController.updateForCurrentAppearance()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
