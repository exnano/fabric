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
                .frame(minWidth: 840, minHeight: 560)
        }
        .defaultSize(width: 1_040, height: 680)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
    }
}

@MainActor
final class FabricApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fabric is an LSUIElement menu-bar app, so explicitly activate it when the
        // management window is presented at launch. This brings the native window
        // forward without adding a persistent Dock icon.
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
