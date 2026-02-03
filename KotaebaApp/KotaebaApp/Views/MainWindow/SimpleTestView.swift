import SwiftUI

/// Simple test view with text field to test transcription locally
struct SimpleTestView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var transcribedText: String = ""
    @State private var setupStatus: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status & Debug Info
            VStack(alignment: .leading, spacing: 8) {
                Text("Test & Debug")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Constants.UI.textPrimary)

                HStack {
                    Circle()
                        .fill(stateManager.state.statusColor)
                        .frame(width: 10, height: 10)

                    Text("Status: \(stateManager.state.statusText)")
                        .font(.system(size: 13))
                        .foregroundColor(Constants.UI.textSecondary)
                }

                Text(setupStatus)
                    .font(.system(size: 12))
                    .foregroundColor(Constants.UI.textSecondary.opacity(0.8))
            }
            .padding(12)
            .background(Constants.UI.surfaceDark)
            .cornerRadius(10)

            // Test Text Field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcription Output")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Constants.UI.textSecondary)

                    Spacer()

                    if !transcribedText.isEmpty {
                        Button("Clear") {
                            transcribedText = ""
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Constants.UI.accentOrange)
                        .buttonStyle(.plain)
                    }
                }

                TextEditor(text: $transcribedText)
                    .font(.system(size: 14))
                    .foregroundColor(Constants.UI.textPrimary)
                    .frame(height: 100)
                    .padding(8)
                    .background(Constants.UI.backgroundDark)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Constants.UI.accentOrange.opacity(0.3), lineWidth: 1)
                    )

                if transcribedText.isEmpty {
                    Text("Press Ctrl+X to record. Text will appear here.")
                        .font(.system(size: 11))
                        .foregroundColor(Constants.UI.textSecondary.opacity(0.6))
                        .padding(.top, -90)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
            }

            // Quick Actions
            HStack(spacing: 12) {
                Button("Force Init Hotkey") {
                    AppStateManager.shared.initializeHotkey()
                    checkStatus()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Constants.UI.accentOrange)
                .cornerRadius(6)
                .buttonStyle(.plain)

                Button("Mark Setup Complete") {
                    UserDefaults.standard.set(true, forKey: Constants.Setup.setupCompletedKey)
                    AppStateManager.shared.initializeHotkey()
                    checkStatus()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Constants.UI.successGreen)
                .cornerRadius(6)
                .buttonStyle(.plain)
                
                Button("Test Insertion") {
                    testTextInsertion()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Constants.UI.textSecondary)
                .cornerRadius(6)
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(16)
        .background(Constants.UI.surfaceDark.opacity(0.5))
        .cornerRadius(12)
        .onChange(of: stateManager.currentTranscription) { oldValue, newValue in
            if !newValue.isEmpty {
                transcribedText += newValue + " "
            }
        }
        .onAppear {
            checkStatus()
        }
    }

    private func checkStatus() {
        let setupComplete = SetupManager.isSetupComplete
        let permissions = PermissionManager.getPermissionStatus()
        let hotkeyInitialized = "hotkey initialized" // We can't actually check this easily

        setupStatus = """
        Setup: \(setupComplete ? "✅" : "❌ NOT COMPLETE")
        Accessibility: \(permissions.accessibility ? "✅" : "❌")
        Microphone: \(permissions.microphone ? "✅" : "❌")
        Hotkey: Ctrl+X
        """
    }
    
    private func testTextInsertion() {
        print("[SimpleTestView] Testing text insertion...")
        let inserter = TextInserter()
        inserter.insertText("Test insertion ")
    }
}

#Preview {
    SimpleTestView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
