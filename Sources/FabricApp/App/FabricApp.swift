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
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

@MainActor
final class FabricApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
