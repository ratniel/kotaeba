import SwiftUI

/// Model selection dropdown view
struct ModelSelectionView: View {
    @EnvironmentObject var stateManager: AppStateManager
    @State private var isShowingCustomModelSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Constants.UI.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Menu {
                ForEach(stateManager.availableModels, id: \.identifier) { model in
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
                                Text(model.summary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if stateManager.selectedModel.identifier == model.identifier {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Constants.UI.accentOrange)
                            }
                        }
                    }
                }

                Divider()

                Button {
                    isShowingCustomModelSheet = true
                } label: {
                    Label("Add Custom Model...", systemImage: "plus")
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(stateManager.selectedModel.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Constants.UI.textPrimary)

                            // Model download status badge
                            HStack(spacing: 4) {
                                Image(systemName: stateManager.modelDownloadStatus.icon)
                                    .font(.system(size: 10))
                                Text(stateManager.modelDownloadStatus.displayText)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(stateManager.modelDownloadStatus.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(stateManager.modelDownloadStatus.color.opacity(0.15))
                            .clipShape(.rect(cornerRadius: 4))
                        }

                        Text(stateManager.selectedModel.description)
                            .font(.system(size: 12))
                            .foregroundStyle(Constants.UI.textSecondary)

                        Text("\(stateManager.selectedModel.languageCoverage) • \(stateManager.selectedModel.summary)")
                            .font(.system(size: 11))
                            .foregroundStyle(Constants.UI.textSecondary.opacity(0.85))
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Constants.UI.textSecondary)
                }
                .padding(12)
                .background(Constants.UI.surfaceDark)
                .clipShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(stateManager.isModelSelectionLocked)
            .help(stateManager.modelSelectionLockMessage ?? "Choose the speech model.")
            .sheet(isPresented: $isShowingCustomModelSheet) {
                CustomModelSheet()
                    .environmentObject(stateManager)
            }

            if stateManager.modelDownloadStatus == .downloading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Downloading \(stateManager.selectedModel.name)...")
                            .font(.system(size: 12))
                            .foregroundStyle(Constants.UI.textSecondary)

                        Spacer()

                        if let progress = stateManager.modelDownloadProgress {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Constants.UI.textSecondary.opacity(0.8))
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
                        .foregroundStyle(Constants.UI.textSecondary)

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
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Constants.UI.accentOrange)
                        .clipShape(.rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = stateManager.modelDownloadError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Constants.UI.recordingRed)
            }
        }
        .task {
            // Check model status on appear
            await stateManager.checkModelDownloadStatus()
        }
    }
}

private struct CustomModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var stateManager: AppStateManager
    @State private var modelIdentifier = ""

    private var trimmedIdentifier: String {
        modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedIdentifier.isEmpty && !stateManager.customModelValidationStatus.isRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Model")
                .font(.headline)

            TextField("owner/model-name", text: $modelIdentifier)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(stateManager.customModelValidationStatus.isRunning)

            if stateManager.customModelValidationStatus.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(stateManager.customModelValidationStatus.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = stateManager.customModelValidationError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Constants.UI.recordingRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .disabled(stateManager.customModelValidationStatus.isRunning)

                Button("Add Model") {
                    Task {
                        let didAdd = await stateManager.addCustomModel(identifier: trimmedIdentifier)
                        if didAdd {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            stateManager.clearCustomModelValidationMessage()
        }
    }
}

#Preview {
    ModelSelectionView()
        .environmentObject(AppStateManager.shared)
        .padding()
        .background(Constants.UI.backgroundDark)
}
