import SwiftUI

/// Server status and control panel with modern design
struct ServerControlView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section Header
            Text("Server Status")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Constants.UI.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            // Status Card with modern gradient border effect
            ZStack {
                // Gradient border when active
                if stateManager.state == .serverRunning || stateManager.state == .recording {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Constants.UI.successGreen.opacity(0.3),
                                    Constants.UI.accentOrange.opacity(0.3)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: 8)
                }

                // Main card
                HStack(spacing: 14) {
                    // Status Indicator with pulsing effect
                    ZStack {
                        if stateManager.state == .recording {
                            Circle()
                                .fill(Constants.UI.recordingRed.opacity(0.3))
                                .frame(width: 24, height: 24)
                                .scaleEffect(isHovering ? 1.5 : 1.3)
                                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isHovering)
                        }

                        Circle()
                            .fill(stateManager.state.statusColor)
                            .frame(width: 12, height: 12)
                            .shadow(color: stateManager.state.statusColor.opacity(0.6), radius: 6)
                    }

                    // Status Text
                    VStack(alignment: .leading, spacing: 5) {
                        Text(statusTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Constants.UI.textPrimary)

                        Text(statusSubtitle)
                            .font(.system(size: 13))
                            .foregroundColor(Constants.UI.textSecondary)
                    }

                    Spacer()

                    // Control Button with modern style
                    Button(action: toggleServer) {
                        HStack(spacing: 6) {
                            Image(systemName: buttonIcon)
                                .font(.system(size: 12, weight: .semibold))

                            Text(buttonTitle)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(buttonTextColor)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                if !isButtonDisabled {
                                    Capsule()
                                        .fill(buttonBackgroundColor)
                                        .shadow(color: buttonShadowColor, radius: 6, x: 0, y: 2)
                                } else {
                                    Capsule()
                                        .fill(Constants.UI.surfaceDark)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isButtonDisabled)
                    .scaleEffect(isHovering && !isButtonDisabled ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Constants.UI.surfaceDark)
                        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
                )
            }
            .onHover { hovering in
                isHovering = hovering
            }

            if stateManager.state == .idle || stateManager.state == .serverRunning {
                ModelSelectionView()
            }
        }
        .onAppear {
            isHovering = stateManager.state == .recording
        }
    }

    // MARK: - Computed Properties

    private var statusTitle: String {
        switch stateManager.state {
        case .idle: return "Offline"
        case .serverStarting: return "Starting..."
        case .serverRunning: return "Online"
        case .connecting: return "Connecting..."
        case .recording: return "Recording"
        case .processing: return "Processing..."
        case .error: return "Error"
        }
    }

    private var statusSubtitle: String {
        switch stateManager.state {
        case .idle: return "Server is offline"
        case .serverStarting: return "Loading model: \(stateManager.selectedModel.name)"
        case .serverRunning: return "Ready • \(stateManager.selectedModel.name)"
        case .connecting: return "Establishing connection..."
        case .recording: return "Listening to your voice..."
        case .processing: return "Transcribing audio..."
        case .error(let msg): return msg
        }
    }

    private var buttonTitle: String {
        switch stateManager.state {
        case .idle, .error: return "Start Server"
        case .serverStarting: return "Starting..."
        default: return "Stop Server"
        }
    }

    private var buttonIcon: String {
        switch stateManager.state {
        case .idle, .error: return "power"
        case .serverStarting: return "arrow.clockwise"
        default: return "stop.fill"
        }
    }

    private var buttonBackgroundColor: Color {
        switch stateManager.state {
        case .idle, .error:
            return Constants.UI.accentOrange
        case .serverStarting:
            return Constants.UI.surfaceDark
        default:
            return Constants.UI.recordingRed.opacity(0.15)
        }
    }

    private var buttonTextColor: Color {
        switch stateManager.state {
        case .idle, .error:
            return .white
        case .serverStarting:
            return Constants.UI.textSecondary
        default:
            return Constants.UI.recordingRed
        }
    }

    private var buttonShadowColor: Color {
        switch stateManager.state {
        case .idle, .error:
            return Constants.UI.accentOrange.opacity(0.4)
        default:
            return Color.clear
        }
    }

    private var isButtonDisabled: Bool {
        stateManager.state == .serverStarting || stateManager.state == .connecting
    }

    // MARK: - Actions

    private func toggleServer() {
        Task {
            switch stateManager.state {
            case .idle, .error:
                await stateManager.startServer()
            default:
                stateManager.stopServer()
            }
        }
    }
}

#Preview {
    ServerControlView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
