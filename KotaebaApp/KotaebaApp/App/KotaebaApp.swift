import SwiftUI
import AppKit

/// Main app entry point
/// 
/// KotaebaApp is a menubar app with an optional main window.
/// The app runs in background and responds to global hotkeys.
@main
struct KotaebaApp: App {
    // AppDelegate handles menubar icon and app lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Shared state manager
    @StateObject private var stateManager = Constants.isRunningTests
        ? AppStateManager.testingInstance
        : AppStateManager.shared

    var body: some Scene {
        Window("Kotaeba", id: "main") {
            if Constants.isRunningTests {
                EmptyView()
                    .environmentObject(stateManager)
            } else {
                MainWindowView()
                    .environmentObject(stateManager)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            if Constants.isRunningTests {
                EmptyView()
                    .environmentObject(stateManager)
            } else {
                SettingsView()
                    .environmentObject(stateManager)
                    .frame(width: 520, height: 420)
            }
        }
    }
}
