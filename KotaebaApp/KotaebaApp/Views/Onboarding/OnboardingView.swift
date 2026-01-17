import SwiftUI

/// First-run onboarding flow
///
/// Guides user through:
/// 1. Welcome
/// 2. Permission requests
/// 3. Dependency installation
/// 4. Completion
struct OnboardingView: View {
    @StateObject private var setupManager = SetupManager()
    @State private var currentStep: OnboardingStep = .welcome
    @State private var permissionStatus = PermissionManager.getPermissionStatus()
    
    enum OnboardingStep {
        case welcome
        case permissions
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
                    WelcomeStepView(onNext: { currentStep = .permissions })
                    
                case .permissions:
                    PermissionsStepView(
                        permissionStatus: $permissionStatus,
                        onNext: { currentStep = .setup }
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
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
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
                FeatureRowView(icon: "bolt.fill", text: "Press Ctrl+X to dictate anywhere")
                FeatureRowView(icon: "brain.head.profile", text: "Powered by Apple MLX Whisper")
                FeatureRowView(icon: "lock.fill", text: "100% offline and private")
            }
            
            Spacer()
            
            Button(action: onNext) {
                Text("Get Started")
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

// MARK: - Permissions Step

struct PermissionsStepView: View {
    @Binding var permissionStatus: PermissionStatus
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Constants.UI.accentOrange)
                
                Text("Permissions Required")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Constants.UI.textPrimary)
                
                Text("Kotaeba needs these permissions to work")
                    .foregroundColor(Constants.UI.textSecondary)
            }
            
            VStack(spacing: 16) {
                PermissionRowView(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "To capture your voice",
                    isGranted: permissionStatus.microphone,
                    onRequest: {
                        Task {
                            let granted = await PermissionManager.requestMicrophonePermission()
                            permissionStatus = PermissionManager.getPermissionStatus()
                        }
                    }
                )
                
                PermissionRowView(
                    icon: "hand.point.up.left.fill",
                    title: "Accessibility",
                    description: "For global hotkeys and text insertion",
                    isGranted: permissionStatus.accessibility,
                    onRequest: {
                        PermissionManager.requestAccessibilityPermission()
                        // Poll for permission grant
                        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                            permissionStatus = PermissionManager.getPermissionStatus()
                            if permissionStatus.accessibility {
                                timer.invalidate()
                            }
                        }
                    }
                )
            }
            
            Spacer()
            
            Button(action: onNext) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(permissionStatus.allGranted ? Constants.UI.accentOrange : Color.gray)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(!permissionStatus.allGranted)
        }
    }
}

struct PermissionRowView: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onRequest: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Constants.UI.accentOrange)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Constants.UI.textPrimary)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(Constants.UI.textSecondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Constants.UI.successGreen)
            } else {
                Button("Grant") {
                    onRequest()
                }
                .buttonStyle(.plain)
                .foregroundColor(Constants.UI.accentOrange)
            }
        }
        .padding(16)
        .background(Constants.UI.surfaceDark)
        .cornerRadius(10)
    }
}

// MARK: - Setup Step

struct SetupStepView: View {
    @ObservedObject var setupManager: SetupManager
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "gear.badge")
                    .font(.system(size: 48))
                    .foregroundColor(Constants.UI.accentOrange)
                
                Text("Installing Dependencies")
                    .font(.system(size: 28, weight: .bold))
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
                        
                        Button("Retry") {
                            Task {
                                await setupManager.runSetup()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Constants.UI.accentOrange)
                    }
                    .padding()
                } else if setupManager.isComplete {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Constants.UI.successGreen)
                        
                        Text("Setup Complete!")
                            .font(.headline)
                    }
                }
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
            }
        }
        .onAppear {
            if !setupManager.isSettingUp && !setupManager.isComplete {
                Task {
                    await setupManager.runSetup()
                }
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
                    text: "Press Ctrl+X to begin recording"
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
