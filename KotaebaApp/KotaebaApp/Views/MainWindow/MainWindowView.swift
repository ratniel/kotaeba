import SwiftUI

/// Main application window
///
/// Contains:
/// - Server status and controls
/// - Model selection
/// - Recording mode selection
/// - Statistics display
/// - Quick access to settings
struct MainWindowView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Constants.UI.backgroundDark,
                    Color(hex: "151517")
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header
                    HeaderView()
                        .padding(.top, 16)

                    // Server Control Card
                    ServerControlView()

                    // Simple Test View with debug info
                    SimpleTestView()

                    // Model Selection
                    if stateManager.state == .idle || stateManager.state == .serverRunning {
                        ModelSelectionView()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Recording Mode
                    RecordingModeView()

                    // Statistics - Compact
                    StatisticsView()

                    Spacer(minLength: 12)

                    // Footer
                    FooterView()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .frame(width: Constants.UI.mainWindowWidth, height: Constants.UI.mainWindowHeight)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Header

struct HeaderView: View {
    var body: some View {
        HStack(spacing: 12) {
            // App icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Constants.UI.accentOrange,
                                Constants.UI.accentOrange.opacity(0.7)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Kotaeba")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Constants.UI.textPrimary)

                Text("Voice-to-Text Assistant")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Constants.UI.textSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    var body: some View {
        HStack {
            Text("v\(Constants.appVersion)")
                .font(.caption2)
                .foregroundColor(Constants.UI.textSecondary.opacity(0.6))

            Spacer()

            Button(action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                    Text("Settings")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(Constants.UI.textSecondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainWindowView()
        .environmentObject(AppStateManager.shared)
}
