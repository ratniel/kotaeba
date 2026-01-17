import SwiftUI

/// Server status and control panel
struct ServerControlView: View {
    @EnvironmentObject var stateManager: AppStateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            Text("Server")
                .font(.headline)
                .foregroundColor(Constants.UI.textSecondary)
            
            // Status Card
            HStack(spacing: 16) {
                // Status Indicator
                Circle()
                    .fill(stateManager.state.statusColor)
                    .frame(width: 12, height: 12)
                    .shadow(color: stateManager.state.statusColor.opacity(0.5), radius: 4)
                
                // Status Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Constants.UI.textPrimary)
                    
                    Text(statusSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Constants.UI.textSecondary)
                }
                
                Spacer()
                
                // Control Button
                Button(action: toggleServer) {
                    Text(buttonTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(buttonTextColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(buttonBackgroundColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isButtonDisabled)
            }
            .padding(16)
            .background(Constants.UI.surfaceDark)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusTitle: String {
        switch stateManager.state {
        case .idle: return "Stopped"
        case .serverStarting: return "Starting..."
        case .serverRunning: return "Running"
        case .connecting: return "Connecting..."
        case .recording: return "Recording"
        case .processing: return "Processing..."
        case .error(let msg): return "Error"
        }
    }
    
    private var statusSubtitle: String {
        switch stateManager.state {
        case .idle: return "Server is not running"
        case .serverStarting: return "Please wait..."
        case .serverRunning: return "Ready for \(Constants.Hotkey.defaultDisplayString)"
        case .connecting: return "Connecting to server..."
        case .recording: return "Listening..."
        case .processing: return "Transcribing..."
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
    
    private var buttonBackgroundColor: Color {
        switch stateManager.state {
        case .idle, .error:
            return Constants.UI.accentOrange
        case .serverStarting:
            return Constants.UI.surfaceDark
        default:
            return Constants.UI.recordingRed.opacity(0.2)
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
