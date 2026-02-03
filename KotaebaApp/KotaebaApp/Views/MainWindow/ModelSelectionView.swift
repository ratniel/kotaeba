import SwiftUI

/// Model selection dropdown view
struct ModelSelectionView: View {
    @EnvironmentObject var stateManager: AppStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Constants.UI.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Menu {
                ForEach(Constants.Models.availableModels, id: \.identifier) { model in
                    Button {
                        // Change model asynchronously
                        Task {
                            await stateManager.setSelectedModel(model)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(model.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if stateManager.selectedModel.identifier == model.identifier {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Constants.UI.accentOrange)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(stateManager.selectedModel.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Constants.UI.textPrimary)

                            // Model download status badge
                            HStack(spacing: 4) {
                                Image(systemName: stateManager.modelDownloadStatus.icon)
                                    .font(.system(size: 10))
                                Text(stateManager.modelDownloadStatus.displayText)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(stateManager.modelDownloadStatus.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(stateManager.modelDownloadStatus.color.opacity(0.15))
                            .cornerRadius(4)
                        }

                        Text(stateManager.selectedModel.description)
                            .font(.system(size: 12))
                            .foregroundColor(Constants.UI.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(Constants.UI.textSecondary)
                }
                .padding(12)
                .background(Constants.UI.surfaceDark)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(stateManager.state == .serverStarting || stateManager.state == .connecting || stateManager.state == .recording)
        }
        .task {
            // Check model status on appear
            await stateManager.checkModelDownloadStatus()
        }
    }
}

#Preview {
    ModelSelectionView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
