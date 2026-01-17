import SwiftUI
import SwiftData

/// Main app entry point
/// 
/// KotaebaApp is a menubar app with an optional main window.
/// The app runs in background and responds to global hotkeys.
@main
struct KotaebaApp: App {
    // AppDelegate handles menubar icon and app lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Shared state manager
    @StateObject private var stateManager = AppStateManager.shared
    
    // SwiftData container for statistics persistence
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TranscriptionSession.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        // Main settings/stats window
        Window("Kotaeba", id: "main") {
            MainWindowView()
                .environmentObject(stateManager)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        // Settings window (accessible via Preferences menu item)
        Settings {
            SettingsView()
                .environmentObject(stateManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
