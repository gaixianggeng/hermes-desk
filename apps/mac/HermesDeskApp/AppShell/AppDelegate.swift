import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installApplicationIcon()

        DispatchQueue.main.async {
            self.revealMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        revealMainWindow()
        return true
    }

    private func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func installApplicationIcon() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 256, weight: .regular)
        guard let image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "Hermes Desk")?
            .withSymbolConfiguration(configuration) else {
            return
        }
        image.isTemplate = false
        NSApp.applicationIconImage = image
    }
}
