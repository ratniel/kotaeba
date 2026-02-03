import SwiftUI

/// Permission status view to help diagnose accessibility and microphone permissions
struct PermissionStatusView: View {
    @State private var permissionStatus = PermissionManager.getPermissionStatus()
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                    permissionStatus = PermissionManager.getPermissionStatus()
                }
            }) {
                HStack {
                    Image(systemName: permissionStatus.allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundColor(permissionStatus.allGranted ? Constants.UI.successGreen : Constants.UI.recordingRed)

                    Text("Permissions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Constants.UI.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    if !permissionStatus.allGranted {
                        Text("\(permissionStatus.missingPermissions.count) missing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Constants.UI.recordingRed.opacity(0.8))
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Constants.UI.textSecondary)
                }
            }
            .buttonStyle(.plain)

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
                                PermissionManager.openAccessibilitySettings()
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
                                    permissionStatus = PermissionManager.getPermissionStatus()
                                }
                            }
                        }
                    )

                    if !permissionStatus.allGranted {
                        // Help text
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Constants.UI.accentOrange.opacity(0.6))

                            Text("Grant permissions in System Settings to use the app")
                                .font(.system(size: 11))
                                .foregroundColor(Constants.UI.textSecondary.opacity(0.8))
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
            permissionStatus = PermissionManager.getPermissionStatus()
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
                    .foregroundColor(isGranted ? Constants.UI.successGreen : Constants.UI.recordingRed)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Constants.UI.textPrimary)

                    Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(isGranted ? Constants.UI.successGreen.opacity(0.8) : Constants.UI.recordingRed.opacity(0.8))
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(Constants.UI.textSecondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Action button
            if !isGranted {
                Button(action: action) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
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
        .padding()
        .background(Constants.UI.backgroundDark)
}
