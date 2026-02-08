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
    private var onboardingWindow: NSWindow?
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenubar()
        setupRecordingBar()
        observeStateChanges()
        observeWindowVisibility()
        checkFirstRun()
        Log.app.info("App logs at \(Constants.supportDirectory.appendingPathComponent("logs/kotaeba.log").path)")
        
        // Dock icon visibility is toggled based on whether a standard window is open.
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean shutdown
        AppStateManager.shared.shutdown()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppStateManager.shared.shutdownForTermination()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
        switch state {
        case .idle, .error:
            menu.addItem(NSMenuItem(title: "Start Server", action: #selector(startServer), keyEquivalent: "s"))
        case .serverRunning, .recording:
            menu.addItem(NSMenuItem(title: "Stop Server", action: #selector(stopServer), keyEquivalent: "s"))
        default:
            break
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
        let setupCompleted = isSetupReady()

        if !setupCompleted {
            closeMainWindowIfNeeded()
            // Show onboarding window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openOnboarding()
            }
            return
        }

        closeOnboardingIfNeeded()
        // Initialize hotkey manager
        AppStateManager.shared.initializeHotkey()
        openMainWindow()

        if !PermissionManager.checkAllPermissions() {
            PermissionManager.requestAccessibilityPermission()
            Task {
                _ = await PermissionManager.requestMicrophonePermissionOrOpenSettings()
            }
        }
    }

    private func isSetupReady() -> Bool {
        let venvExists = FileManager.default.fileExists(atPath: Constants.Setup.venvPath.path)
        let pythonExists = FileManager.default.isExecutableFile(atPath: Constants.Setup.pythonPath.path)
        let venvReady = venvExists || pythonExists
        if venvReady && !SetupManager.isSetupComplete {
            UserDefaults.standard.set(true, forKey: Constants.Setup.setupCompletedKey)
        }
        return venvReady
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
        let setupCompleted = isSetupReady()
        if !setupCompleted {
            closeMainWindowIfNeeded()
            openOnboarding()
            return
        }

        setDockVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open via WindowGroup
            NSApp.sendAction(NSSelectorFromString(("showWindow:")), to: nil, from: nil)
        }
    }
    
    @objc private func openOnboarding() {
        setDockVisible(true)

        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Kotaeba"
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func closeMainWindowIfNeeded() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.close()
        }
    }

    private func closeOnboardingIfNeeded() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Dock Visibility

    private func observeWindowVisibility() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateDockVisibility()
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        updateDockVisibility()
    }

    private func updateDockVisibility() {
        let hasVisibleStandardWindow = NSApp.windows.contains { window in
            guard window.isVisible else { return false }
            return isStandardAppWindow(window)
        }
        setDockVisible(hasVisibleStandardWindow)
    }

    private func isStandardAppWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel {
            return false
        }
        return window.styleMask.contains(.titled)
    }

    private func setDockVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
