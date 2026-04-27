import SwiftUI

struct TranscriptionHistoryView: View {
    @EnvironmentObject private var stateManager: AppStateManager
    @State private var isConfirmingClearHistory = false

    var body: some View {
        AppBackground {
            VStack(alignment: .leading, spacing: 16) {
                header

                if stateManager.recentTranscriptionSessions.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 10) {
                            ForEach(stateManager.recentTranscriptionSessions, id: \.id) { session in
                                TranscriptionHistoryRow(session: session)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(20)
        }
        .task {
            stateManager.refreshStatistics()
        }
        .confirmationDialog(
            "Clear History and Statistics?",
            isPresented: $isConfirmingClearHistory
        ) {
            Button("Clear History and Statistics", role: .destructive) {
                clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved transcription sessions and resets aggregate statistics.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Constants.UI.textPrimary)

                Text("\(stateManager.recentTranscriptionSessions.count) recent sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Constants.UI.textSecondary)
            }

            Spacer()

            Button(action: refreshHistory) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh history")

            Button(role: .destructive, action: requestClearHistoryConfirmation) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Clear transcription history")
            .disabled(stateManager.recentTranscriptionSessions.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Constants.UI.textSecondary.opacity(0.7))

            Text("No saved transcriptions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Constants.UI.textPrimary)

            Text("Completed recordings appear here.")
                .font(.system(size: 12))
                .foregroundStyle(Constants.UI.textSecondary)
        }
    }

    private func refreshHistory() {
        stateManager.refreshStatistics()
    }

    private func requestClearHistoryConfirmation() {
        isConfirmingClearHistory = true
    }

    private func clearHistory() {
        stateManager.clearTranscriptionHistory()
    }
}

private struct TranscriptionHistoryRow: View {
    let session: TranscriptionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.startTime, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Constants.UI.textSecondary)

                Spacer()

                insertionBadge
            }

            Text(displayText)
                .font(.system(size: 14))
                .foregroundStyle(Constants.UI.textPrimary)
                .lineLimit(4)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                HistoryMetadataLabel(icon: "textformat", text: "\(session.wordCount) words")
                HistoryMetadataLabel(icon: "timer", text: formatDuration(session.duration))

                if let sourceAppName = session.sourceAppName, !sourceAppName.isEmpty {
                    HistoryMetadataLabel(icon: "app", text: sourceAppName)
                }

                Spacer(minLength: 0)
            }

            if let modelIdentifier = session.modelIdentifier, !modelIdentifier.isEmpty {
                Text(modelIdentifier)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Constants.UI.textSecondary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .background(Constants.UI.surfaceDark, in: .rect(cornerRadius: 8))
    }

    private var displayText: String {
        guard let text = session.transcribedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return "No final transcript was returned."
        }
        return text
    }

    @ViewBuilder
    private var insertionBadge: some View {
        if let error = session.insertionError, !error.isEmpty {
            Label("Insertion failed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Constants.UI.recordingRed)
                .help(error)
        } else if let method = session.insertionMethod, !method.isEmpty {
            Label(method, systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Constants.UI.successGreen)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let minutes = seconds / 60
        let remainder = seconds % 60

        if minutes > 0 {
            return "\(minutes)m \(remainder)s"
        }
        return "\(remainder)s"
    }
}

private struct HistoryMetadataLabel: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Constants.UI.textSecondary)
            .lineLimit(1)
    }
}

#Preview {
    TranscriptionHistoryView()
        .environmentObject(AppStateManager.shared)
}
