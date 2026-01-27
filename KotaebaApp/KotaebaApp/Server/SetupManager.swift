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
            
            // Step 4: Pre-download models (optional, can be done on first use)
            // await updateStep(.downloadingModels)
            // try await downloadModels()
            
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
        // Check common locations
        let paths = [
            "\(NSHomeDirectory())/.local/bin/uv",
            "/usr/local/bin/uv",
            "/opt/homebrew/bin/uv"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }
    
    private func installUV() async throws {
        let script = """
        curl -LsSf https://astral.sh/uv/install.sh | sh
        """
        try await runShellCommand(script)
    }
    
    private func createVirtualEnvironment() async throws {
        let uvPath = findUVPath() ?? "~/.local/bin/uv"
        let supportPath = Constants.supportDirectory.path
        
        let script = """
        export PATH="$HOME/.local/bin:$PATH"
        cd "\(supportPath)"
        \(uvPath) venv --python 3.11
        """
        try await runShellCommand(script)
    }

    private func installDependencies() async throws {
        let uvPath = findUVPath() ?? "~/.local/bin/uv"
        let supportPath = Constants.supportDirectory.path
        
        let script = """
        export PATH="$HOME/.local/bin:$PATH"
        cd "\(supportPath)"
        # Initialize pyproject.toml if it doesn't exist
        if [ ! -f "pyproject.toml" ]; then
            \(uvPath) init --app --no-readme --name kotaeba-server
        fi
        # Install dependencies
        \(uvPath) add mlx-audio mlx fastapi uvicorn websockets
        """
        try await runShellCommand(script)
    }
    
    private func downloadModels() async throws {
        let uvPath = findUVPath() ?? "~/.local/bin/uv"
        let supportPath = Constants.supportDirectory.path
        
        let script = """
        export PATH="$HOME/.local/bin:$PATH"
        cd "\(supportPath)"
        \(uvPath) run python -c "from mlx_audio.stt import STT; STT()"
        """
        try await runShellCommand(script)
    }
    
    private func findUVPath() -> String? {
        let paths = [
            "\(NSHomeDirectory())/.local/bin/uv",
            "/usr/local/bin/uv",
            "/opt/homebrew/bin/uv"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    private func runShellCommand(_ command: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Log output
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                if let output = String(data: handle.availableData, encoding: .utf8), !output.isEmpty {
                    print("[Setup] \(output)", terminator: "")
                }
            }
            
            process.terminationHandler = { process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: SetupError.commandFailed(errorMessage))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Setup Errors

enum SetupError: LocalizedError {
    case commandFailed(String)
    case uvNotFound
    case venvCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Setup command failed: \(message)"
        case .uvNotFound:
            return "uv package manager not found after installation"
        case .venvCreationFailed:
            return "Failed to create Python virtual environment"
        }
    }
}

