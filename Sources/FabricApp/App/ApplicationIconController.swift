import AppKit

/// Selects the Dock/Application Switcher icon that best matches the current macOS
/// appearance. Finder uses the bundled ICNS fallback when Fabric is not running.
@MainActor
enum ApplicationIconController {
    static func updateForCurrentAppearance() {
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua
        let resourceName = isDark ? "FabricIcon-Dark" : "FabricIcon-Light"

        guard
            let resourceURL = Bundle.main.url(
                forResource: resourceName,
                withExtension: "png"
            ),
            let image = NSImage(contentsOf: resourceURL)
        else {
            // The ICNS declared in Info.plist remains a safe fallback if a resource
            // cannot be loaded from a development run outside an app bundle.
            return
        }

        image.isTemplate = false
        NSApplication.shared.applicationIconImage = image
    }
}
