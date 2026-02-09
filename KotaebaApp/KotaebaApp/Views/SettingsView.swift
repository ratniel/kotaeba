import SwiftUI

/// Settings and preferences window
struct SettingsView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @AppStorage(Constants.UserDefaultsKeys.autoStartServer) private var autoStartServer = false
    @AppStorage(Constants.UserDefaultsKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(Constants.UserDefaultsKeys.serverHost) private var serverHost = Constants.Server.defaultHost
    @AppStorage(Constants.UserDefaultsKeys.serverPort) private var serverPort = Constants.Server.defaultPort
    @AppStorage(Constants.UserDefaultsKeys.useClipboardFallback) private var useClipboardFallback = false
    @AppStorage(Constants.UserDefaultsKeys.safeModeEnabled) private var safeModeEnabled = true
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                autoStartServer: $autoStartServer,
                launchAtLogin: $launchAtLogin,
                serverHost: $serverHost,
                serverPort: $serverPort
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            HotkeySettingsView()
                .tabItem {
                    Label("Hotkey", systemImage: "command")
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
    @Binding var autoStartServer: Bool
    @Binding var launchAtLogin: Bool
    @Binding var serverHost: String
    @Binding var serverPort: Int
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

                Stepper(value: $serverPort, in: 1...65535) {
                    HStack {
                        Text("Port")
                        Spacer()
                        Text("\(serverPort)")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Server")
            }

            Section {
                SecureField("Hugging Face token (optional)", text: $tokenDraft)

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

                Text(hasStoredToken ? "A token is stored securely in Keychain." : "No token stored.")
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
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hasStoredToken = KeychainSecretStore.string(for: Constants.SecureSettingsKeys.huggingFaceToken) != nil
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

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @EnvironmentObject var stateManager: AppStateManager
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Current Hotkey")
                    Spacer()
                    Text(Constants.Hotkey.defaultDisplayString)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(6)
                }
                
                Text("Customizable hotkeys coming in future update")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Hotkey Configuration")
            }
            
            Section {
                RecordingModeView(showsHeader: false)
                
                Text(stateManager.recordingMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Recording Mode")
            }
        }
        .formStyle(.grouped)
        .padding()
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
