import SwiftUI

/// Content view for the recording bar overlay
///
/// Displays:
/// - Recording indicator (pulsing red dot)
/// - Audio visualizer
/// - Live transcription text
struct RecordingBarView: View {
    @EnvironmentObject var stateManager: AppStateManager
    
    var body: some View {
        HStack(spacing: Constants.UI.recordingBarPadding) {
            // Recording indicator
            RecordingIndicatorView()
            
            // Audio visualizer
            AudioVisualizerView()
                .frame(width: CGFloat(Constants.UI.visualizerBarCount) * (Constants.UI.visualizerBarWidth + Constants.UI.visualizerBarSpacing))
            
            // Transcription text
            TranscriptionTextView(text: stateManager.currentTranscription)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Constants.UI.recordingBarPadding)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Constants.UI.recordingBarCornerRadius, style: .continuous)
                .fill(Constants.UI.backgroundDark.opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.UI.recordingBarCornerRadius, style: .continuous)
                .strokeBorder(Constants.UI.accentOrange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Recording Indicator

struct RecordingIndicatorView: View {
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Constants.UI.recordingRed)
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear {
                    isPulsing = true
                }
            
            Text("REC")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Constants.UI.recordingRed)
        }
    }
}

// MARK: - Transcription Text

struct TranscriptionTextView: View {
    let text: String
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text.isEmpty ? "Listening..." : text)
                .font(.system(size: 14))
                .foregroundColor(text.isEmpty ? Constants.UI.textSecondary : Constants.UI.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Preview

#Preview {
    RecordingBarView()
        .environmentObject(AppStateManager.shared)
        .frame(width: 800, height: Constants.UI.recordingBarHeight)
        .padding()
        .background(Color.black.opacity(0.3))
}
