import AppKit
import SwiftUI

/// Settings and preferences window
struct SettingsView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @AppStorage(Constants.UserDefaultsKeys.autoStartServer) private var autoStartServer = false
    @AppStorage(Constants.UserDefaultsKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(Constants.UserDefaultsKeys.serverHost) private var serverHost = Constants.Server.defaultHost
    @AppStorage(Constants.UserDefaultsKeys.serverPort) private var serverPort = Constants.Server.defaultPort
    @AppStorage(Constants.UserDefaultsKeys.showDiagnosticsUI) private var showDiagnosticsUI = Constants.FeatureFlags.defaultDiagnosticsUI
    @AppStorage(Constants.UserDefaultsKeys.useClipboardFallback) private var useClipboardFallback = false
    @AppStorage(Constants.UserDefaultsKeys.safeModeEnabled) private var safeModeEnabled = true
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                autoStartServer: $autoStartServer,
                launchAtLogin: $launchAtLogin,
                serverHost: $serverHost,
                serverPort: $serverPort,
                showDiagnosticsUI: $showDiagnosticsUI
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            HotkeySettingsView()
                .tabItem {
                    Label("Hotkey", systemImage: "command")
                }

            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }
            
            TranscriptionSettingsView(
                useClipboardFallback: $useClipboardFallback,
                safeModeEnabled: $safeModeEnabled
            )
            .tabItem {
                Label("Transcription", systemImage: "text.bubble")
            }
            
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @Binding var autoStartServer: Bool
    @Binding var launchAtLogin: Bool
    @Binding var serverHost: String
    @Binding var serverPort: Int
    @Binding var showDiagnosticsUI: Bool
    @State private var serverPortText = ""
    @State private var tokenDraft = ""
    @State private var hasStoredToken = false
    @State private var keychainMessage: String?
    
    var body: some View {
        Form {
            Section {
                Toggle("Start server automatically on launch", isOn: $autoStartServer)
                
                Toggle("Launch Kotaeba at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Text("Startup")
            }
            
            Section {
                TextField("Host", text: $serverHost)

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: $serverPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                        .help("Enter a port between 1 and 65535.")
                }
            } header: {
                Text("Server")
            }

            Section {
                SecureField("Hugging Face API key (optional)", text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                HStack {
                    Button("Save Token") {
                        saveToken()
                    }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Token") {
                        clearToken()
                    }
                    .disabled(!hasStoredToken)
                }

                Text(hasStoredToken ? "An API key is stored securely in Keychain." : "No API key stored.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let keychainMessage {
                    Text(keychainMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Authentication")
            }

            Section {
                PermissionSettingsRow(
                    icon: "hand.tap.fill",
                    title: "Accessibility",
                    description: "Required for the global hotkey and inserting text into other apps.",
                    isGranted: stateManager.permissionStatus.accessibility,
                    buttonTitle: stateManager.permissionStatus.accessibility ? "Open Settings" : "Grant Access",
                    action: {
                        if stateManager.permissionStatus.accessibility {
                            PermissionManager.openAccessibilitySettings()
                        } else {
                            stateManager.requestAccessibilityPermission()
                        }
                    }
                )

                PermissionSettingsRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to capture audio for transcription.",
                    isGranted: stateManager.permissionStatus.microphone,
                    buttonTitle: stateManager.permissionStatus.microphone ? "Open Settings" : "Grant Access",
                    action: {
                        Task {
                            if stateManager.permissionStatus.microphone {
                                PermissionManager.openMicrophoneSettings()
                            } else {
                                _ = await PermissionManager.requestMicrophonePermissionOrOpenSettings()
                                stateManager.refreshPermissionStatus(source: "settingsMicrophoneGrant")
                            }
                        }
                    }
                )

                HStack {
                    Button("Recheck Permissions") {
                        stateManager.recheckPermissionsAndHotkey()
                    }

                    if !stateManager.permissionStatus.allGranted {
                        Button("Reveal Running App") {
                            PermissionManager.revealRunningAppInFinder()
                        }
                    }
                }

                if !stateManager.permissionStatus.allGranted {
                    Text("Grant access to the exact app build currently running, then come back and recheck.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(PermissionManager.runningAppPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Permissions")
            }

            Section {
                Toggle("Show test tools in sidebar", isOn: $showDiagnosticsUI)

                Text("Keeps the Test App screen available so you can verify permissions, insertion, and runtime behavior from the installed app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Developer")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hasStoredToken = KeychainSecretStore.string(for: Constants.SecureSettingsKeys.huggingFaceToken) != nil
            syncServerPortText()
            stateManager.refreshPermissionStatus(source: "settingsAppear")
        }
        .onChange(of: serverPortText) { _, newValue in
            updateServerPortText(newValue)
        }
        .onChange(of: serverPort) { _, _ in
            syncServerPortText()
        }
    }

    private func syncServerPortText() {
        let normalizedPort = min(max(serverPort, 1), 65535)
        if normalizedPort != serverPort {
            serverPort = normalizedPort
        }

        let normalizedText = String(normalizedPort)
        if serverPortText != normalizedText {
            serverPortText = normalizedText
        }
    }

    private func updateServerPortText(_ rawValue: String) {
        let digitsOnly = rawValue.filter(\.isNumber)
        if digitsOnly != rawValue {
            serverPortText = digitsOnly
            return
        }

        guard !digitsOnly.isEmpty else {
            return
        }

        guard let parsedPort = Int(digitsOnly) else {
            return
        }

        let clampedPort = min(max(parsedPort, 1), 65535)
        if serverPort != clampedPort {
            serverPort = clampedPort
        }

        let normalizedText = String(clampedPort)
        if normalizedText != digitsOnly {
            serverPortText = normalizedText
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // TODO: Implement launch at login using SMLoginItemSetEnabled
        // This requires additional setup with a helper app
        Log.ui.info("Launch at login: \(enabled)")
    }

    private func saveToken() {
        do {
            let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            try KeychainSecretStore.upsert(token, for: Constants.SecureSettingsKeys.huggingFaceToken)
            tokenDraft = ""
            hasStoredToken = true
            keychainMessage = "Token saved."
        } catch {
            keychainMessage = error.localizedDescription
        }
    }

    private func clearToken() {
        do {
            try KeychainSecretStore.delete(Constants.SecureSettingsKeys.huggingFaceToken)
            hasStoredToken = false
            keychainMessage = "Token removed."
        } catch {
            keychainMessage = error.localizedDescription
        }
    }
}

private struct PermissionSettingsRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isGranted ? Constants.UI.successGreen : Constants.UI.accentOrange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)

                    Text(isGranted ? "Granted" : "Needs Access")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isGranted ? Constants.UI.successGreen : Constants.UI.accentOrange).opacity(0.15))
                        .clipShape(.rect(cornerRadius: 999))
                }

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Button(buttonTitle, action: action)
        }
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var isCapturingShortcut = false
    @State private var shortcutMessage: String?
    @State private var shortcutMessageIsWarning = false
    @State private var shortcutEventMonitor: Any?
    @State private var shouldRestoreHotkeyAfterCapture = false
    @State private var showsShortcutHelp = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Current Hotkey")
                    Spacer()
                    Text(stateManager.currentHotkey.displayString)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(.rect(cornerRadius: 6))
                }

                HStack(spacing: 8) {
                    Button(isCapturingShortcut ? "Press Shortcut..." : "Change...") {
                        beginShortcutCapture()
                    }
                    .disabled(isCapturingShortcut)

                    Button("Reset") {
                        saveShortcut(.default)
                    }
                    .disabled(stateManager.currentHotkey == .default)

                    Button {
                        showsShortcutHelp.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(HotkeyShortcutRules.avoidanceHelpText)
                    .popover(isPresented: $showsShortcutHelp, arrowEdge: .trailing) {
                        ShortcutAvoidancePopover()
                    }

                    if isCapturingShortcut {
                        Button("Cancel") {
                            cancelShortcutCapture(message: nil)
                        }
                    }
                }

                if isCapturingShortcut {
                    Text("Press the new shortcut, or Esc to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let shortcutMessage {
                    Text(shortcutMessage)
                        .font(.caption)
                        .foregroundStyle(shortcutMessageIsWarning ? Constants.UI.accentOrange : Color.secondary)
                }
            } header: {
                Text("Hotkey Configuration")
            }
            
            Section {
                RecordingModeView(showsHeader: false)

                if let prompt = stateManager.recordingModePromptMessage {
                    RecordingModePromptView(message: prompt) {
                        stateManager.clearRecordingModePrompt()
                    }
                }
                
                Text(stateManager.recordingMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Recording Mode")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if isCapturingShortcut {
                cancelShortcutCapture(message: nil)
            }
        }
        .onDisappear {
            cancelShortcutCapture(message: nil)
        }
    }

    private func beginShortcutCapture() {
        if isCapturingShortcut {
            finishShortcutCapture(restoreHotkey: true)
        }

        shortcutMessage = nil
        shortcutMessageIsWarning = false
        shouldRestoreHotkeyAfterCapture = stateManager.suspendHotkeyForShortcutCapture()
        isCapturingShortcut = true

        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handleShortcutEvent(event)
            return nil
        }) else {
            finishShortcutCapture(restoreHotkey: true)
            shortcutMessage = "Could not start shortcut capture."
            shortcutMessageIsWarning = true
            return
        }
        shortcutEventMonitor = monitor
    }

    private func handleShortcutEvent(_ event: NSEvent) {
        if event.keyCode == Constants.Hotkey.escapeKeyCode {
            cancelShortcutCapture(message: nil)
            return
        }

        let shortcut = HotkeyShortcut(
            keyCode: event.keyCode,
            modifiers: HotkeyModifiers(modifierFlags: event.modifierFlags)
        )

        switch HotkeyShortcutRules.validation(for: shortcut) {
        case .valid(let caution):
            saveShortcut(shortcut, caution: caution)
        case .invalid(let message):
            shortcutMessage = message
            shortcutMessageIsWarning = true
        }
    }

    private func saveShortcut(_ shortcut: HotkeyShortcut, caution: String? = nil) {
        removeShortcutEventMonitor()
        isCapturingShortcut = false
        let shouldRestoreHotkey = shouldRestoreHotkeyAfterCapture
        shouldRestoreHotkeyAfterCapture = false
        stateManager.setHotkeyShortcut(shortcut)
        stateManager.resumeHotkeyAfterShortcutCapture(shouldRestore: shouldRestoreHotkey)
        shortcutMessage = caution ?? "Hotkey set to \(shortcut.displayString)."
        shortcutMessageIsWarning = caution != nil
    }

    private func cancelShortcutCapture(message: String?) {
        finishShortcutCapture(restoreHotkey: true)
        shortcutMessage = message
        shortcutMessageIsWarning = false
    }

    private func finishShortcutCapture(restoreHotkey: Bool) {
        removeShortcutEventMonitor()
        isCapturingShortcut = false
        let shouldRestoreHotkey = shouldRestoreHotkeyAfterCapture
        shouldRestoreHotkeyAfterCapture = false
        if restoreHotkey {
            stateManager.resumeHotkeyAfterShortcutCapture(shouldRestore: shouldRestoreHotkey)
        }
    }

    private func removeShortcutEventMonitor() {
        if let shortcutEventMonitor {
            NSEvent.removeMonitor(shortcutEventMonitor)
            self.shortcutEventMonitor = nil
        }
    }
}

private struct ShortcutAvoidancePopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shortcuts to Avoid")
                .font(.headline)

            ForEach(HotkeyShortcutRules.avoidanceSuggestions) { suggestion in
                HStack {
                    Text(suggestion.shortcut.displayString)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 58, alignment: .leading)

                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 220)
    }
}

// MARK: - Audio Settings

struct AudioSettingsView: View {
    @EnvironmentObject var stateManager: AppStateManager

    private var selectedDevice: AudioInputDevice? {
        stateManager.audioInputDevices.first { $0.id == stateManager.selectedAudioInputDeviceID }
    }

    var body: some View {
        Form {
            Section {
                Picker("Input", selection: selectedDeviceBinding) {
                    ForEach(stateManager.audioInputDevices) { device in
                        Text(device.settingsDisplayName)
                            .tag(device.id)
                    }
                }

                HStack {
                    Button("Refresh") {
                        stateManager.refreshAudioInputDevices()
                        stateManager.refreshPermissionStatus(source: "audioSettingsRefresh")
                    }

                    Spacer()

                    Text(selectedStatusText)
                        .font(.caption)
                        .foregroundStyle(selectedStatusColor)
                }

                Text("Kotaeba keeps transcription audio at 16 kHz mono PCM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Microphone")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            stateManager.refreshPermissionStatus(source: "audioSettingsAppear")
            stateManager.refreshAudioInputDevices()
        }
    }

    private var selectedDeviceBinding: Binding<String> {
        Binding(
            get: { stateManager.selectedAudioInputDeviceID },
            set: { stateManager.setSelectedAudioInputDeviceID($0) }
        )
    }

    private var selectedStatusText: String {
        guard stateManager.permissionStatus.microphone else {
            return "Microphone access required"
        }

        guard let selectedDevice else {
            return "Using System Default"
        }

        if selectedDevice.isSystemDefault {
            return "Using System Default"
        }

        return selectedDevice.isAvailable ? "Available" : "Unavailable; falling back"
    }

    private var selectedStatusColor: Color {
        guard stateManager.permissionStatus.microphone else {
            return Constants.UI.accentOrange
        }

        guard let selectedDevice, !selectedDevice.isSystemDefault else {
            return .secondary
        }

        return selectedDevice.isAvailable ? Constants.UI.successGreen : Constants.UI.accentOrange
    }
}

// MARK: - Transcription Settings

struct TranscriptionSettingsView: View {
    @Binding var useClipboardFallback: Bool
    @Binding var safeModeEnabled: Bool
    
    var body: some View {
        Form {
            Section {
                Toggle("Safe mode (prevent newlines)", isOn: $safeModeEnabled)

                Text("Replaces newlines with spaces to avoid accidental command execution in terminals.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Use clipboard fallback for text insertion", isOn: $useClipboardFallback)
                
                Text("Enable if text insertion doesn't work in some apps. Temporarily modifies clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Clipboard fallback may not preserve all data types or metadata and can overwrite recent clipboard changes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Text Insertion")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(Constants.UI.accentOrange)
            
            Text("Kotaeba")
                .font(.system(size: 28, weight: .bold))
            
            Text("Version \(Constants.appVersion)")
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text("Speech-to-text transcription powered by")
                    .foregroundColor(.secondary)
                
                Text("MLX Whisper")
                    .font(.headline)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com")!)
                Text("•")
                    .foregroundColor(.secondary)
                Link("Report Issue", destination: URL(string: "https://github.com")!)
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppStateManager.shared)
}
