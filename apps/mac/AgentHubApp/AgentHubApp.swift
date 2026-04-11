import AppKit
import SwiftUI

@main
struct AgentHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppStateStore()

    var body: some Scene {
        Window("Agent Hub", id: WindowRouter.mainWindowID) {
            DashboardView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1_120, height: 700)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Agent Hub", systemImage: appState.menuBarSymbolName) {
            MenuBarScene()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsScene()
                .environmentObject(appState)
                .frame(width: 540, height: 360)
        }
    }
}
