import SwiftUI

/// Recording mode selection view
struct RecordingModeView: View {
    @EnvironmentObject var stateManager: AppStateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            Text("Recording")
                .font(.headline)
                .foregroundColor(Constants.UI.textSecondary)
            
            VStack(spacing: 12) {
                // Hotkey Display
                HStack {
                    Text("Hotkey:")
                        .foregroundColor(Constants.UI.textSecondary)
                    
                    Text(Constants.Hotkey.defaultDisplayString)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(Constants.UI.accentOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Constants.UI.surfaceDark)
                        .cornerRadius(6)
                    
                    Spacer()
                }
                
                Divider()
                    .background(Constants.UI.surfaceDark)
                
                // Mode Selection
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        ModeOptionView(
                            mode: mode,
                            isSelected: stateManager.recordingMode == mode
                        ) {
                            stateManager.setRecordingMode(mode)
                        }
                    }
                }
            }
            .padding(16)
            .background(Constants.UI.surfaceDark)
            .cornerRadius(12)
        }
    }
}

// MARK: - Mode Option

struct ModeOptionView: View {
    let mode: RecordingMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Radio Button
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Constants.UI.accentOrange : Constants.UI.textSecondary,
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Circle()
                            .fill(Constants.UI.accentOrange)
                            .frame(width: 10, height: 10)
                    }
                }
                
                // Mode Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Constants.UI.textPrimary)
                    
                    Text(mode.description)
                        .font(.system(size: 12))
                        .foregroundColor(Constants.UI.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecordingModeView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
