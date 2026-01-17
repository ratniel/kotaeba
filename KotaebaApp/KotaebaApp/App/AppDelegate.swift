import AppKit
import SwiftUI
import Combine

/// AppDelegate handles menubar icon and application lifecycle
///
/// Responsibilities:
/// - Create and manage the menubar status item
/// - Handle app launch/termination
/// - Show/hide recording bar window
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem!
    private var recordingBarWindowController: RecordingBarWindowController?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenubar()
        setupRecordingBar()
        observeStateChanges()
        checkFirstRun()
        
        // Hide dock icon (menubar app behavior)
        // Note: Also set LSUIElement = YES in Info.plist for production
        // For development, we keep the dock icon for easier debugging
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean shutdown
        AppStateManager.shared.shutdown()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when window closes - we're a menubar app
        return false
    }
    
    // MARK: - Menubar Setup
    
    private func setupMenubar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem.button else { return }
        
        // Default icon
        button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "Kotaeba")
        button.image?.isTemplate = true  // Adapts to menubar appearance
        
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        let state = AppStateManager.shared.state
        
        // Status header
        let statusItem = NSMenuItem(title: state.statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        if let dot = createStatusDot(for: state) {
            statusItem.image = dot
        }
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Server control
        if state == .idle || state == .error("") {
            menu.addItem(NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s"))
        } else if state == .serverRunning || state == .recording {
            menu.addItem(NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "s"))
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Recording mode indicator
        let modeItem = NSMenuItem(title: "Mode: \(AppStateManager.shared.recordingMode.displayName)", action: nil, keyEquivalent: "")
        modeItem.isEnabled = false
        menu.addItem(modeItem)
        
        let hotkeyItem = NSMenuItem(title: "Hotkey: \(Constants.Hotkey.defaultDisplayString)", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open main window
        menu.addItem(NSMenuItem(title: "Open Kotaeba...", action: #selector(openMainWindow), keyEquivalent: "o"))
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        menu.addItem(NSMenuItem(title: "Quit Kotaeba", action: #selector(quit), keyEquivalent: "q"))
        
        self.statusItem.menu = menu
    }
    
    private func createStatusDot(for state: AppState) -> NSImage? {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size, flipped: false) { rect in
            let color: NSColor
            switch state {
            case .idle: color = .systemGray
            case .serverStarting, .connecting, .processing: color = .systemOrange
            case .serverRunning: color = .systemGreen
            case .recording: color = .systemRed
            case .error: color = .systemRed
            }
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return image
    }
    
    // MARK: - Recording Bar
    
    private func setupRecordingBar() {
        recordingBarWindowController = RecordingBarWindowController()
    }
    
    private func showRecordingBar() {
        recordingBarWindowController?.showBar()
    }
    
    private func hideRecordingBar() {
        recordingBarWindowController?.hideBar()
    }
    
    // MARK: - State Observation
    
    private func observeStateChanges() {
        // Update menubar icon based on state
        AppStateManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateMenubarIcon(for: state)
                self?.updateMenu()
                
                // Show/hide recording bar
                if state == .recording {
                    self?.showRecordingBar()
                } else {
                    self?.hideRecordingBar()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateMenubarIcon(for state: AppState) {
        guard let button = statusItem.button else { return }
        
        let iconName: String
        switch state {
        case .idle:
            iconName = "mic.circle"
        case .serverStarting, .connecting:
            iconName = "mic.circle.fill"
        case .serverRunning:
            iconName = "mic.circle"
        case .recording:
            iconName = "mic.fill"
        case .processing:
            iconName = "ellipsis.circle"
        case .error:
            iconName = "exclamationmark.triangle"
        }
        
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Kotaeba")
        button.image?.isTemplate = state != .recording  // Red tint when recording
        
        if state == .recording {
            button.contentTintColor = .systemRed
        } else {
            button.contentTintColor = nil
        }
    }
    
    // MARK: - First Run
    
    private func checkFirstRun() {
        let setupCompleted = UserDefaults.standard.bool(forKey: Constants.Setup.setupCompletedKey)
        if !setupCompleted {
            // Show onboarding window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openOnboarding()
            }
        } else {
            // Initialize hotkey manager
            AppStateManager.shared.initializeHotkey()
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func startServer() {
        Task {
            await AppStateManager.shared.startServer()
        }
    }
    
    @objc private func stopServer() {
        AppStateManager.shared.stopServer()
    }
    
    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open via WindowGroup
            NSApp.sendAction(Selector(("showWindow:")), to: nil, from: nil)
        }
    }
    
    @objc private func openOnboarding() {
        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        onboardingWindow.title = "Welcome to Kotaeba"
        onboardingWindow.contentView = NSHostingView(rootView: OnboardingView())
        onboardingWindow.center()
        onboardingWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
