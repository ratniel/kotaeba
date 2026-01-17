import SwiftUI

/// Main application window
///
/// Contains:
/// - Server status and controls
/// - Recording mode selection
/// - Statistics display
/// - Quick access to settings
struct MainWindowView: View {
    @EnvironmentObject var stateManager: AppStateManager
    
    var body: some View {
        ZStack {
            // Background
            Constants.UI.backgroundDark
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                HeaderView()
                
                // Server Control
                ServerControlView()
                
                // Recording Mode
                RecordingModeView()
                
                // Statistics
                StatisticsView()
                
                Spacer()
                
                // Footer
                FooterView()
            }
            .padding(24)
        }
        .frame(width: Constants.UI.mainWindowWidth, height: Constants.UI.mainWindowHeight)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Header

struct HeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundColor(Constants.UI.accentOrange)
            
            Text("Kotaeba")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Constants.UI.textPrimary)
            
            Spacer()
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    var body: some View {
        HStack {
            Text("v\(Constants.appVersion)")
                .font(.caption)
                .foregroundColor(Constants.UI.textSecondary)
            
            Spacer()
            
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(Constants.UI.accentOrange)
        }
    }
}

// MARK: - Preview

#Preview {
    MainWindowView()
        .environmentObject(AppStateManager.shared)
}
