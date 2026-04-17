import Combine
import Foundation

/// Manages first-run preparation for a bundled speech runtime and local model cache.
@MainActor
final class SetupManager: ObservableObject {

    @Published var isSettingUp = false
    @Published var currentStep = ""
    @Published var progress: Double = 0.0
    @Published var error: String?
    @Published var isComplete = false

    enum SetupStep: String {
        case checkingRuntime = "Checking speech runtime..."
        case preparingModel = "Preparing default speech model..."
        case complete = "Kotaeba is ready!"

        var progressValue: Double {
            switch self {
            case .checkingRuntime:
                return 0.2
            case .preparingModel:
                return 0.65
            case .complete:
                return 1.0
            }
        }
    }

    static var isSetupComplete: Bool {
        Constants.Setup.isRuntimeAvailable
    }

    static var runtimePathDescription: String {
        Constants.Setup.runtimeDisplayPath
    }

    static var runtimeSourceDescription: String {
        Constants.Setup.runtimeSourceDisplayName
    }

    init() {
        isComplete = Self.isSetupComplete
    }

    func runSetup() async {
        guard !isSettingUp else { return }

        isSettingUp = true
        isComplete = false
        error = nil

        do {
            try FileManager.default.createDirectory(
                at: Constants.supportDirectory,
                withIntermediateDirectories: true
            )

            await updateStep(.checkingRuntime)
            guard Constants.Setup.isRuntimeAvailable else {
                throw SetupError.runtimeUnavailable
            }

            await updateStep(.preparingModel)
            try await prepareDefaultModelIfNeeded()

            await updateStep(.complete)
            isComplete = true
            isSettingUp = false
        } catch {
            self.error = error.localizedDescription
            isSettingUp = false
            isComplete = false
        }
    }

    private func updateStep(_ step: SetupStep) async {
        currentStep = step.rawValue
        progress = step.progressValue
    }

    private func prepareDefaultModelIfNeeded() async throws {
        let serverManager = ServerManager()
        let modelIdentifier = Constants.Models.defaultModel.identifier

        if try await serverManager.checkModelExists(modelIdentifier) {
            progress = 1.0
            return
        }

        try await serverManager.downloadModel(modelIdentifier) { [weak self] downloadProgress in
            Task { @MainActor in
                self?.progress = 0.3 + (downloadProgress * 0.65)
            }
        }
    }
}

enum SetupError: LocalizedError {
    case runtimeUnavailable

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "Kotaeba couldn't find its speech runtime. Reinstall the app or restore the development runtime before continuing."
        }
    }
}
