import SwiftUI

/// First-run onboarding flow focused on permissions and model preparation.
struct OnboardingView: View {
    @StateObject private var setupManager = SetupManager()
    @State private var currentStep: OnboardingStep = .welcome
    @State private var permissionStatus = PermissionManager.getPermissionStatus()
    @State private var isRequestingPermissions = false
    @State private var permissionHint: String?

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
                        permissionStatus: permissionStatus,
                        isRequestingPermissions: isRequestingPermissions,
                        permissionHint: permissionHint,
                        onNext: handleWelcomeAction,
                        onRecheck: refreshPermissionStatus
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
            refreshPermissionStatus()
            guard currentStep == .welcome, permissionStatus.allGranted else { return }
            isRequestingPermissions = false
            permissionHint = nil
        }
    }

    private func handleWelcomeAction() {
        if permissionStatus.allGranted {
            currentStep = .setup
            return
        }

        isRequestingPermissions = true
        permissionHint = "Grant Accessibility and microphone access, then return to Kotaeba."

        Task { @MainActor in
            PermissionManager.requestAccessibilityPermission()
            _ = await PermissionManager.requestMicrophonePermissionOrOpenSettings()
            refreshPermissionStatus()

            if permissionStatus.allGranted {
                isRequestingPermissions = false
                permissionHint = nil
                currentStep = .setup
            } else {
                isRequestingPermissions = false
            }
        }
    }

    private func refreshPermissionStatus() {
        permissionStatus = PermissionManager.getPermissionStatus()
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let permissionStatus: PermissionStatus
    let isRequestingPermissions: Bool
    let permissionHint: String?
    let onNext: () -> Void
    let onRecheck: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Constants.UI.accentOrange)

            VStack(spacing: 12) {
                Text("Welcome to Kotaeba")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Constants.UI.textPrimary)

                Text("Grant permissions once, then download the default speech model.")
                    .font(.system(size: 16))
                    .foregroundStyle(Constants.UI.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                FeatureRowView(icon: "bolt.fill", text: "Hold Ctrl+X to dictate anywhere")
                FeatureRowView(icon: "brain.head.profile", text: "Uses a local speech runtime on your Mac")
                FeatureRowView(icon: "lock.fill", text: "Downloads models once, then stays private and offline")
            }

            PermissionSummaryCard(permissionStatus: permissionStatus, permissionHint: permissionHint, onRecheck: onRecheck)

            Spacer()

            Button(action: onNext) {
                Text(buttonTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Constants.UI.accentOrange)
                    .clipShape(.rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isRequestingPermissions)
        }
    }

    private var buttonTitle: String {
        if permissionStatus.allGranted {
            return "Continue"
        }
        return isRequestingPermissions ? "Checking Permissions..." : "Grant Permissions"
    }
}

struct FeatureRowView: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Constants.UI.accentOrange)
                .frame(width: 24)

            Text(text)
                .foregroundStyle(Constants.UI.textPrimary)
        }
    }
}

struct PermissionSummaryCard: View {
    let permissionStatus: PermissionStatus
    let permissionHint: String?
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PermissionStatusRow(title: "Accessibility", isGranted: permissionStatus.accessibility)
            PermissionStatusRow(title: "Microphone", isGranted: permissionStatus.microphone)

            if let permissionHint, !permissionStatus.allGranted {
                Text(permissionHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Constants.UI.textSecondary)
            }

            if !permissionStatus.allGranted {
                Button("Recheck") {
                    onRecheck()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Constants.UI.accentOrange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.UI.surfaceDark)
        .clipShape(.rect(cornerRadius: 12))
    }
}

struct PermissionStatusRow: View {
    let title: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? Constants.UI.successGreen : Constants.UI.recordingRed)

            Text(title)
                .foregroundStyle(Constants.UI.textPrimary)

            Spacer()

            Text(isGranted ? "Granted" : "Required")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Constants.UI.textSecondary)
        }
    }
}

// MARK: - Setup Step

struct SetupStepView: View {
    @ObservedObject var setupManager: SetupManager
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text("Kotaeba")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.UI.accentOrange)

                Text("Prepare Your Model")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Constants.UI.textPrimary)

                Text("We'll verify the speech runtime and download the default model for instant dictation.")
                    .foregroundStyle(Constants.UI.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                if setupManager.isSettingUp {
                    ProgressView(value: setupManager.progress)
                        .progressViewStyle(.linear)
                        .tint(Constants.UI.accentOrange)

                    Text(setupManager.currentStep)
                        .font(.system(size: 14))
                        .foregroundStyle(Constants.UI.textSecondary)
                } else if let error = setupManager.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Constants.UI.recordingRed)

                        Text("Preparation Failed")
                            .font(.headline)

                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)
                } else if setupManager.isComplete {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Constants.UI.successGreen)

                        Text("Model Ready!")
                            .font(.headline)
                    }
                } else {
                    Text("Ready to prepare the default speech model.")
                        .font(.system(size: 14))
                        .foregroundStyle(Constants.UI.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Runtime")
                    .font(.caption)
                    .foregroundStyle(Constants.UI.textSecondary)

                Text(Constants.Setup.runtimeSourceDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.UI.textPrimary)

                Text(Constants.Setup.runtimeDisplayPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Constants.UI.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Constants.UI.surfaceDark)
                    .clipShape(.rect(cornerRadius: 8))
            }

            Spacer()

            if setupManager.isComplete {
                Button(action: onComplete) {
                    Text("Finish")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Constants.UI.accentOrange)
                        .clipShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: prepareModel) {
                    Text(setupManager.isSettingUp ? "Preparing..." : "Download Default Model")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Constants.UI.accentOrange)
                        .clipShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(setupManager.isSettingUp)
            }

            if setupManager.error != nil {
                Button("Retry") {
                    prepareModel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Constants.UI.accentOrange)
            }
        }
    }

    private func prepareModel() {
        Task {
            await setupManager.runSetup()
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
                .foregroundStyle(Constants.UI.successGreen)

            VStack(spacing: 12) {
                Text("All Set!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Constants.UI.textPrimary)

                Text("You're ready to start dictating")
                    .font(.system(size: 16))
                    .foregroundStyle(Constants.UI.textSecondary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                InstructionRowView(number: 1, text: "Start the server from the menu bar or main window")
                InstructionRowView(number: 2, text: "Hold Ctrl+X to begin recording")
                InstructionRowView(number: 3, text: "Speak naturally and insert text at the cursor")
            }

            Spacer()

            Button(action: {
                NSApplication.shared.keyWindow?.close()
                AppStateManager.shared.initializeHotkey()
            }) {
                Text("Start Using Kotaeba")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Constants.UI.accentOrange)
                    .clipShape(.rect(cornerRadius: 10))
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
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Constants.UI.accentOrange)
                .clipShape(Circle())

            Text(text)
                .foregroundStyle(Constants.UI.textPrimary)
        }
    }
}

#Preview {
    OnboardingView()
}
