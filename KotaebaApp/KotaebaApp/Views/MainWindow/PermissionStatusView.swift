import SwiftUI

/// Permission status view to help diagnose accessibility and microphone permissions
struct PermissionStatusView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var isExpanded = false

    private var permissionStatus: PermissionStatus {
        stateManager.permissionStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse
            HStack {
                Image(systemName: permissionStatus.allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(permissionStatus.allGranted ? Constants.UI.successGreen : Constants.UI.recordingRed)

                Text("Permissions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.UI.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if !permissionStatus.allGranted {
                    Text("\(permissionStatus.missingPermissions.count) missing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Constants.UI.recordingRed.opacity(0.8))
                }

                if isExpanded {
                    Button(action: {
                        stateManager.recheckPermissionsAndHotkey()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Recheck")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Constants.UI.accentOrange)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                        stateManager.refreshPermissionStatus(source: "permissionHeaderToggle")
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Constants.UI.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(spacing: 10) {
                    // Accessibility Permission
                    PermissionRow(
                        icon: "hand.tap.fill",
                        title: "Accessibility",
                        description: "Required for hotkey capture and text insertion",
                        isGranted: permissionStatus.accessibility,
                        action: {
                            if !permissionStatus.accessibility {
                                stateManager.requestAccessibilityPermission()
                            }
                        }
                    )

                    Divider()
                        .background(Constants.UI.surfaceDark)

                    // Microphone Permission
                    PermissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Required for audio recording",
                        isGranted: permissionStatus.microphone,
                        action: {
                            if !permissionStatus.microphone {
                                Task {
                                    _ = await PermissionManager.requestMicrophonePermissionOrOpenSettings()
                                    stateManager.refreshPermissionStatus(source: "microphoneGrant")
                                }
                            }
                        }
                    )

                    if !permissionStatus.allGranted {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Constants.UI.accentOrange.opacity(0.6))

                                Text("Grant access to the exact app build that is currently running.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Constants.UI.textSecondary.opacity(0.8))
                            }

                            Text(PermissionManager.runningAppPath)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Constants.UI.textSecondary.opacity(0.75))
                                .textSelection(.enabled)

                            if PermissionManager.isRunningFromDerivedData {
                                Text("This build is running from Xcode DerivedData. For a permanent Accessibility grant, launch a consistently signed app from a stable location like /Applications.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Constants.UI.accentOrange.opacity(0.85))
                            }

                            HStack(spacing: 10) {
                                Button("Reveal Running App") {
                                    PermissionManager.revealRunningAppInFinder()
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Constants.UI.accentOrange)

                                if !permissionStatus.accessibility {
                                    Button("Open Accessibility Settings") {
                                        PermissionManager.openAccessibilitySettings()
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Constants.UI.textSecondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Constants.UI.surfaceDark)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            stateManager.refreshPermissionStatus(source: "permissionStatusAppear")
        }
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isGranted ? Constants.UI.successGreen.opacity(0.15) : Constants.UI.recordingRed.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isGranted ? Constants.UI.successGreen : Constants.UI.recordingRed)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Constants.UI.textPrimary)

                    Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(isGranted ? Constants.UI.successGreen.opacity(0.8) : Constants.UI.recordingRed.opacity(0.8))
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Constants.UI.textSecondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Action button
            if !isGranted {
                Button(action: action) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Constants.UI.accentOrange)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    PermissionStatusView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
