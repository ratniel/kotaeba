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
            .disabled(stateManager.state == .serverStarting || stateManager.state == .connecting || stateManager.state == .recording || stateManager.modelDownloadStatus == .downloading)

            if stateManager.modelDownloadStatus == .downloading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Downloading \(stateManager.selectedModel.name)...")
                            .font(.system(size: 12))
                            .foregroundColor(Constants.UI.textSecondary)

                        Spacer()

                        if let progress = stateManager.modelDownloadProgress {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Constants.UI.textSecondary.opacity(0.8))
                        }
                    }

                    if let progress = stateManager.modelDownloadProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Constants.UI.accentOrange)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(Constants.UI.accentOrange)
                    }
                }
            } else if stateManager.modelDownloadStatus == .notDownloaded || stateManager.modelDownloadStatus == .unknown {
                HStack(spacing: 10) {
                    Text(stateManager.modelDownloadStatus == .unknown ? "Model status unknown" : "Model not downloaded")
                        .font(.system(size: 12))
                        .foregroundColor(Constants.UI.textSecondary)

                    Spacer()

                    Button {
                        Task {
                            await stateManager.downloadSelectedModel()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Constants.UI.accentOrange)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = stateManager.modelDownloadError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Constants.UI.recordingRed)
            }
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
