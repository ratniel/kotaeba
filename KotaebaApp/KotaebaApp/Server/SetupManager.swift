import Foundation
import Combine

/// Manages first-run setup and dependency installation
///
/// On first launch, this manager:
/// 1. Installs uv (Python package manager) via curl
/// 2. Creates a virtual environment
/// 3. Installs mlx-audio and dependencies
class SetupManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isSettingUp = false
    @Published var currentStep = ""
    @Published var progress: Double = 0.0
    @Published var error: String?
    @Published var isComplete = false
    
    // MARK: - Setup Steps
    
    enum SetupStep: String, CaseIterable {
        case checkingUV = "Checking for uv..."
        case installingUV = "Installing uv package manager..."
        case creatingVenv = "Creating Python environment..."
        case installingDeps = "Installing dependencies (this may take a few minutes)..."
        case downloadingModels = "Downloading ML models..."
        case complete = "Setup complete!"
        
        var progressValue: Double {
            switch self {
            case .checkingUV: return 0.1
            case .installingUV: return 0.2
            case .creatingVenv: return 0.3
            case .installingDeps: return 0.6
            case .downloadingModels: return 0.9
            case .complete: return 1.0
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Check if setup has been completed
    static var isSetupComplete: Bool {
        UserDefaults.standard.bool(forKey: Constants.Setup.setupCompletedKey)
    }
    
    /// Run the full setup process
    func runSetup() async {
        await MainActor.run {
            if isSettingUp || isComplete {
                return
            }
            isSettingUp = true
            error = nil
        }
        
        do {
            // Ensure support directory exists
            try FileManager.default.createDirectory(
                at: Constants.supportDirectory,
                withIntermediateDirectories: true
            )
            
            // Step 1: Check/install uv
            await updateStep(.checkingUV)
            if !isUVInstalled() {
                await updateStep(.installingUV)
                try await installUV()
            }
            
            // Step 2: Create virtual environment
            await updateStep(.creatingVenv)
            try await createVirtualEnvironment()
            
            // Step 3: Install dependencies
            await updateStep(.installingDeps)
            try await installDependencies()
            
            // Step 4: Pre-download default model for a smoother first run
            await updateStep(.downloadingModels)
            try await downloadModels()
            
            // Mark setup complete
            await updateStep(.complete)
            UserDefaults.standard.set(true, forKey: Constants.Setup.setupCompletedKey)
            
            await MainActor.run {
                isComplete = true
                isSettingUp = false
            }
            
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isSettingUp = false
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func updateStep(_ step: SetupStep) async {
        await MainActor.run {
            currentStep = step.rawValue
            progress = step.progressValue
        }
    }
    
    private func isUVInstalled() -> Bool {
        findUVURL() != nil
    }
    
    private func installUV() async throws {
        guard let brewURL = findBrewURL() else {
            throw SetupError.uvInstallUnavailable
        }
        try await ShellCommandRunner.run(
            executableURL: brewURL,
            arguments: ["install", "uv"]
        ) { output in
            Log.setup.info(output)
        }
        guard findUVURL() != nil else {
            throw SetupError.uvNotFoundAfterInstall
        }
    }
    
    private func createVirtualEnvironment() async throws {
        guard let uvURL = findUVURL() else {
            throw SetupError.uvNotFound
        }
        try await ShellCommandRunner.run(
            executableURL: uvURL,
            arguments: ["venv", "--python", "3.11"],
            currentDirectory: Constants.supportDirectory
        ) { output in
            Log.setup.info(output)
        }
    }

    private func installDependencies() async throws {
        guard let uvURL = findUVURL() else {
            throw SetupError.uvNotFound
        }
        let supportDirectory = Constants.supportDirectory
        let pyprojectURL = supportDirectory.appendingPathComponent("pyproject.toml")
        if !FileManager.default.fileExists(atPath: pyprojectURL.path) {
            try await ShellCommandRunner.run(
                executableURL: uvURL,
                arguments: ["init", "--app", "--no-readme", "--name", "kotaeba-server"],
                currentDirectory: supportDirectory
            ) { output in
                Log.setup.info(output)
            }
        }
        try await ShellCommandRunner.run(
            executableURL: uvURL,
            arguments: ["add", "mlx-audio", "mlx", "fastapi", "uvicorn", "websockets"],
            currentDirectory: supportDirectory
        ) { output in
            Log.setup.info(output)
        }
    }
    
    private func downloadModels() async throws {
        let pythonURL = Constants.Setup.pythonPath
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw SetupError.pythonNotFound
        }
        let command = "from mlx_audio.utils import load_model; load_model('\(Constants.Models.defaultModel.identifier)')"
        try await ShellCommandRunner.run(
            executableURL: pythonURL,
            arguments: ["-c", command],
            currentDirectory: Constants.supportDirectory,
            environment: ServerEnvironment.build(model: Constants.Models.defaultModel.identifier)
        ) { output in
            Log.setup.info(output)
        }
    }
    
    private func findUVURL() -> URL? {
        findExecutable(
            named: "uv",
            additionalPaths: [
                "\(NSHomeDirectory())/.local/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin"
            ]
        )
    }

    private func findBrewURL() -> URL? {
        findExecutable(
            named: "brew",
            additionalPaths: [
                "/opt/homebrew/bin",
                "/usr/local/bin"
            ]
        )
    }

    private func findExecutable(named name: String, additionalPaths: [String]) -> URL? {
        var searchPaths = [String]()
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            searchPaths.append(contentsOf: pathEnv.split(separator: ":").map(String.init))
        }
        searchPaths.append(contentsOf: additionalPaths)

        for path in searchPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            let candidate = URL(fileURLWithPath: expandedPath).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
    
}

enum SetupError: LocalizedError {
    case uvInstallUnavailable
    case uvNotFoundAfterInstall
    case uvNotFound
    case pythonNotFound

    var errorDescription: String? {
        switch self {
        case .uvInstallUnavailable:
            return "uv is not installed and Homebrew is unavailable. Please install uv manually and retry setup."
        case .uvNotFoundAfterInstall:
            return "uv installation completed but the executable was not found. Please verify your PATH and retry."
        case .uvNotFound:
            return "uv executable not found. Please install uv and retry setup."
        case .pythonNotFound:
            return "Python environment not found. Please complete setup and retry."
        }
    }
}
