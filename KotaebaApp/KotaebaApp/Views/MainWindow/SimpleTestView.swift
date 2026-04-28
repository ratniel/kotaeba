import SwiftUI

/// Simple test view with text field to test transcription locally
struct SimpleTestView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var transcribedText: String = ""

    private var setupStatus: String {
        """
        Runtime: \(SetupManager.isSetupComplete ? "✅ Ready" : "❌ Missing")
        Runtime Source: \(SetupManager.runtimeSourceDescription)
        Accessibility: \(stateManager.permissionStatus.accessibility ? "✅" : "❌")
        Microphone: \(stateManager.permissionStatus.microphone ? "✅" : "❌")
        Hotkey: \(stateManager.isHotkeyActive ? "✅ Active" : "❌ Inactive")
        Status: \(stateManager.hotkeyStatusMessage)
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status & debug info
            VStack(alignment: .leading, spacing: 8) {
                Text("Debug Tools")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Constants.UI.textPrimary)

                HStack {
                    Circle()
                        .fill(stateManager.state.statusColor)
                        .frame(width: 10, height: 10)

                    Text("Status: \(stateManager.state.statusText)")
                        .font(.system(size: 13))
                        .foregroundStyle(Constants.UI.textSecondary)
                }

                Text(setupStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(Constants.UI.textSecondary.opacity(0.8))
                    .textSelection(.enabled)

                if let error = stateManager.lastInsertionError {
                    Text("Last insertion error: \(error)")
                        .font(.system(size: 12))
                        .foregroundStyle(Constants.UI.recordingRed)
                } else if let method = stateManager.lastInsertionMethod {
                    Text("Last insertion: \(method)")
                        .font(.system(size: 12))
                        .foregroundStyle(Constants.UI.textSecondary.opacity(0.8))
                }

                if let diagnosticDetails = stateManager.lastDiagnosticErrorDetails, !diagnosticDetails.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last runtime error (debug)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Constants.UI.recordingRed)

                        Text(diagnosticDetails)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Constants.UI.textSecondary.opacity(0.9))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(Constants.UI.surfaceDark)
            .clipShape(.rect(cornerRadius: 10))

            // Test Text Field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcription Output")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Constants.UI.textSecondary)

                    Spacer()

                    if !transcribedText.isEmpty {
                        Button("Clear") {
                            transcribedText = ""
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Constants.UI.accentOrange)
                        .buttonStyle(.plain)
                    }
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $transcribedText)
                        .font(.system(size: 14))
                        .foregroundStyle(Constants.UI.textPrimary)
                        .frame(height: 100)
                        .padding(8)
                        .background(Constants.UI.backgroundDark)
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Constants.UI.accentOrange.opacity(0.3), lineWidth: 1)
                        )

                    if transcribedText.isEmpty {
                        Text("Live and completed transcripts will appear here.")
                            .font(.system(size: 11))
                            .foregroundStyle(Constants.UI.textSecondary.opacity(0.6))
                            .padding(.top, 16)
                            .padding(.leading, 14)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Quick Actions
            HStack(spacing: 12) {
                Button("Force Init Hotkey") {
                    stateManager.refreshPermissionsAndHotkey(promptIfMissing: false)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Constants.UI.accentOrange)
                .clipShape(.rect(cornerRadius: 6))
                .buttonStyle(.plain)

                Button("Refresh Runtime") {
                    Task {
                        await stateManager.checkModelDownloadStatus()
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Constants.UI.successGreen)
                .clipShape(.rect(cornerRadius: 6))
                .buttonStyle(.plain)
                
                Button("Test Insertion") {
                    testTextInsertion()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Constants.UI.textSecondary)
                .clipShape(.rect(cornerRadius: 6))
                .buttonStyle(.plain)
                .disabled(!stateManager.permissionStatus.accessibility)

                Spacer()
            }
        }
        .padding(16)
        .background(Constants.UI.surfaceDark.opacity(0.5))
        .clipShape(.rect(cornerRadius: 12))
        .onChange(of: stateManager.currentTranscription) { _, newValue in
            if !newValue.isEmpty {
                transcribedText = newValue
            }
        }
        .onChange(of: stateManager.lastCompletedTranscription) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            transcribedText = newValue
        }
        .onAppear {
            stateManager.refreshPermissionsAndHotkey(promptIfMissing: false)
        }
    }
    
    private func testTextInsertion() {
        Log.ui.info("Testing text insertion...")
        stateManager.testInsertion("Test insertion ")
    }
}

#Preview {
    SimpleTestView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
