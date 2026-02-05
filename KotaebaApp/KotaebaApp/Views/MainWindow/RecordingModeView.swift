import SwiftUI

/// Recording mode selection with modern compact design
struct RecordingModeView: View {
    @EnvironmentObject var stateManager: AppStateManager
    var showsHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                Text("Recording Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Constants.UI.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            HStack(spacing: 10) {
                ForEach(RecordingMode.allCases, id: \.self) { mode in
                    ModeButton(mode: mode, isSelected: stateManager.recordingMode == mode) {
                        guard stateManager.recordingMode != mode else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            stateManager.setRecordingMode(mode)
                        }
                    }
                }
            }
        }
    }
}

struct ModeButton: View {
    let mode: RecordingMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Constants.UI.accentOrange.opacity(0.15) : Color.clear)
                        .frame(width: 40, height: 40)

                    Image(systemName: mode == .hold ? "hand.tap.fill" : "repeat")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? Constants.UI.accentOrange : Constants.UI.textSecondary)
                }

                // Title
                Text(mode == .hold ? "Hold" : "Toggle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? Constants.UI.textPrimary : Constants.UI.textSecondary)

                // Description
                Text(mode == .hold ? "Press & hold" : "Click to toggle")
                    .font(.system(size: 11))
                    .foregroundColor(Constants.UI.textSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)

                if isSelected {
                    Text("Selected")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Constants.UI.accentOrange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Constants.UI.accentOrange.opacity(0.15))
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Constants.UI.surfaceDark : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Constants.UI.accentOrange.opacity(0.3) : Constants.UI.textSecondary.opacity(0.1),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: isSelected ? Constants.UI.accentOrange.opacity(0.2) : Color.clear, radius: 8)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(.rect(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    RecordingModeView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
