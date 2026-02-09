import SwiftUI

/// Test text view to display transcriptions locally in the app
/// This helps verify the recording → transcription flow works before testing global insertion
struct TranscriptionTestView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var transcriptionHistory: [TranscriptionEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Transcription")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Constants.UI.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button(action: clearTranscriptions) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Clear")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Constants.UI.textSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Scrollable transcription area
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Current partial transcription
                    if !stateManager.currentTranscription.isEmpty {
                        TranscriptionBubble(
                            text: stateManager.currentTranscription,
                            isPartial: true
                        )
                    }

                    // History (final transcriptions)
                    ForEach(transcriptionHistory.reversed()) { entry in
                        TranscriptionBubble(
                            text: entry.text,
                            isPartial: false,
                            timestamp: entry.timestamp
                        )
                    }

                    if transcriptionHistory.isEmpty && stateManager.currentTranscription.isEmpty {
                        EmptyStateView()
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Constants.UI.backgroundDark.opacity(0.5))
            )
        }
        .onChange(of: stateManager.currentTranscription) { oldValue, newValue in
            // When transcription changes and is final (goes from value to empty), save it
            if !oldValue.isEmpty && newValue.isEmpty && stateManager.state == .recording {
                addTranscription(oldValue)
            }
        }
    }

    private func addTranscription(_ text: String) {
        let entry = TranscriptionEntry(text: text, timestamp: Date())
        transcriptionHistory.insert(entry, at: 0)

        // Keep only last 10
        if transcriptionHistory.count > 10 {
            transcriptionHistory.removeLast()
        }
    }

    private func clearTranscriptions() {
        transcriptionHistory.removeAll()
    }
}

// MARK: - Transcription Bubble

struct TranscriptionBubble: View {
    let text: String
    let isPartial: Bool
    var timestamp: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isPartial ? Constants.UI.accentOrange.opacity(0.6) : Constants.UI.successGreen.opacity(0.6))
                    .frame(width: 6, height: 6)

                if let timestamp = timestamp {
                    Text(formatTime(timestamp))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Constants.UI.textSecondary.opacity(0.6))
                } else if isPartial {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Constants.UI.accentOrange.opacity(0.8))
                }

                Spacer()

                if isPartial {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Constants.UI.accentOrange)
                }
            }

            Text(text)
                .font(.system(size: 13, weight: isPartial ? .medium : .regular))
                .foregroundColor(Constants.UI.textPrimary.opacity(isPartial ? 0.9 : 1.0))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Constants.UI.surfaceDark.opacity(isPartial ? 0.6 : 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isPartial ? Constants.UI.accentOrange.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 32))
                .foregroundColor(Constants.UI.textSecondary.opacity(0.3))

            Text("Hold Ctrl+X to start recording")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Constants.UI.textSecondary.opacity(0.6))

            Text("Transcriptions will appear here")
                .font(.system(size: 11))
                .foregroundColor(Constants.UI.textSecondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Data Model

struct TranscriptionEntry: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

#Preview {
    TranscriptionTestView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
