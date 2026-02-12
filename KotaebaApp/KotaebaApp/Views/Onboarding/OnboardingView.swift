import SwiftUI

/// First-run onboarding flow
///
/// Guides user through:
/// 1. Welcome
/// 2. Permission requests (system dialogs)
/// 3. Dependency installation
/// 4. Completion
struct OnboardingView: View {
    @StateObject private var setupManager = SetupManager()
    @State private var currentStep: OnboardingStep = .welcome
    @State private var permissionStatus = PermissionManager.getPermissionStatus()
    @State private var isRequestingPermissions = false
    
    enum OnboardingStep {
        case welcome
        case setup
        case complete
    }
    
    var body: some View {
        ZStack {
            Constants.UI.backgroundDark
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                switch currentStep {
                case .welcome:
                    WelcomeStepView(
                        isRequestingPermissions: isRequestingPermissions,
                        onNext: {
                            if permissionStatus.allGranted {
                                currentStep = .setup
                                return
                            }
                            
                            isRequestingPermissions = true
                            Task { @MainActor in
                                Log.ui.info("Starting permission requests")
                                Log.ui.info("Current status - Accessibility: \(permissionStatus.accessibility), Microphone: \(permissionStatus.microphone)")
                                
                                Log.ui.info("Requesting Accessibility permission...")
                                PermissionManager.requestAccessibilityPermission()
                                
                                Log.ui.info("Requesting Microphone permission...")
                                let micResult = await PermissionManager.requestMicrophonePermissionOrOpenSettings()
                                Log.ui.info("Microphone request returned: \(micResult)")
                                
                                permissionStatus = PermissionManager.getPermissionStatus()
                                Log.ui.info("After requests - Accessibility: \(permissionStatus.accessibility), Microphone: \(permissionStatus.microphone)")
                                
                                while !permissionStatus.allGranted {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                    permissionStatus = PermissionManager.getPermissionStatus()
                                    Log.ui.debug("Polling - Accessibility: \(permissionStatus.accessibility), Microphone: \(permissionStatus.microphone)")
                                }
                                
                                Log.ui.info("All permissions granted! Advancing to setup...")
                                isRequestingPermissions = false
                                currentStep = .setup
                            }
                        }
                    )
                    
                case .setup:
                    SetupStepView(
                        setupManager: setupManager,
                        onComplete: { currentStep = .complete }
                    )
                    
                case .complete:
                    CompleteStepView()
                }
            }
            .padding(40)
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionStatus = PermissionManager.getPermissionStatus()
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let isRequestingPermissions: Bool
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Constants.UI.accentOrange)
            
            VStack(spacing: 12) {
                Text("Welcome to Kotaeba")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Constants.UI.textPrimary)
                
                Text("Speech-to-text transcription at your fingertips")
                    .font(.system(size: 16))
                    .foregroundColor(Constants.UI.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRowView(icon: "bolt.fill", text: "Hold Ctrl+X to dictate anywhere")
                FeatureRowView(icon: "brain.head.profile", text: "Powered by Apple MLX Whisper")
                FeatureRowView(icon: "lock.fill", text: "100% offline and private")
            }
            
            Spacer()
            
            Button(action: onNext) {
                Text(isRequestingPermissions ? "Requesting Permissions..." : "Get Started")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Constants.UI.accentOrange)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(isRequestingPermissions)
        }
    }
}

struct FeatureRowView: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Constants.UI.accentOrange)
                .frame(width: 24)
            
            Text(text)
                .foregroundColor(Constants.UI.textPrimary)
        }
    }
}

// MARK: - Setup Step

struct SetupStepView: View {
    @ObservedObject var setupManager: SetupManager
    let onComplete: () -> Void
    
    var body: some View {
        let installPath = Constants.Setup.venvPath.path

        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text("Kotaeba")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(Constants.UI.accentOrange)

                Text("Installing Kotaeba")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Constants.UI.textPrimary)

                Text("Setting up Python environment and ML models")
                    .foregroundColor(Constants.UI.textSecondary)
            }

            VStack(spacing: 16) {
                if setupManager.isSettingUp {
                    ProgressView(value: setupManager.progress)
                        .progressViewStyle(.linear)
                        .tint(Constants.UI.accentOrange)

                    Text(setupManager.currentStep)
                        .font(.system(size: 14))
                        .foregroundColor(Constants.UI.textSecondary)
                } else if let error = setupManager.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Constants.UI.recordingRed)

                        Text("Setup Failed")
                            .font(.headline)

                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                } else if setupManager.isComplete {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Constants.UI.successGreen)

                        Text("Setup Complete!")
                            .font(.headline)
                    }
                } else {
                    Text("Ready to install dependencies")
                        .font(.system(size: 14))
                        .foregroundColor(Constants.UI.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Install Location")
                    .font(.caption)
                    .foregroundColor(Constants.UI.textSecondary)

                Text(installPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Constants.UI.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Constants.UI.surfaceDark)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            if setupManager.isComplete {
                Button(action: onComplete) {
                    Text("Finish")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Constants.UI.accentOrange)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    Task {
                        await setupManager.runSetup()
                    }
                }) {
                    Text(setupManager.isSettingUp ? "Installing..." : "Install Kotaeba")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Constants.UI.accentOrange)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(setupManager.isSettingUp)
            }

            if setupManager.error != nil {
                Button("Retry") {
                    Task {
                        await setupManager.runSetup()
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(Constants.UI.accentOrange)
            }
        }
    }
}

// MARK: - Complete Step

struct CompleteStepView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Constants.UI.successGreen)
            
            VStack(spacing: 12) {
                Text("All Set!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Constants.UI.textPrimary)
                
                Text("You're ready to start dictating")
                    .font(.system(size: 16))
                    .foregroundColor(Constants.UI.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 16) {
                InstructionRowView(
                    number: 1,
                    text: "Start the server from the menubar or main window"
                )
                InstructionRowView(
                    number: 2,
                    text: "Hold Ctrl+X to begin recording"
                )
                InstructionRowView(
                    number: 3,
                    text: "Speak naturally - your words will appear at the cursor"
                )
            }
            
            Spacer()
            
            Button(action: {
                NSApplication.shared.keyWindow?.close()
                AppStateManager.shared.initializeHotkey()
            }) {
                Text("Start Using Kotaeba")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Constants.UI.accentOrange)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }
}

struct InstructionRowView: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Constants.UI.accentOrange)
                .clipShape(Circle())
            
            Text(text)
                .foregroundColor(Constants.UI.textPrimary)
        }
    }
}

#Preview {
    OnboardingView()
}
