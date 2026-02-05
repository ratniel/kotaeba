import Foundation

protocol ServerManaging: AnyObject {
    func start(model: String) async throws
    func stop()
    func stopAndWait(timeout: TimeInterval) async
    func checkModelExists(_ modelIdentifier: String) async throws -> Bool
    func downloadModel(_ modelIdentifier: String, progressHandler: ((Double) -> Void)?) async throws
}

/// Manages the mlx_audio.server Python subprocess
///
/// Responsibilities:
/// - Start/stop the server process
/// - Monitor server health
/// - Capture server output for logging
class ServerManager {
    
    // MARK: - Properties
    
    private var process: Process?
    private var outputPipe: Pipe?
    private var healthCheckTimer: Timer?
    
    private(set) var isRunning = false
    
    // MARK: - Server Control

    /// Start the mlx_audio.server subprocess
    /// The model will be loaded when the first WebSocket connection is established
    func start(model: String) async throws {
        guard !isRunning else {
            throw ServerError.alreadyRunning
        }

        // Ensure support directory exists
        try FileManager.default.createDirectory(
            at: Constants.supportDirectory,
            withIntermediateDirectories: true
        )

        // Check if Python environment is set up
        guard FileManager.default.fileExists(atPath: Constants.Setup.pythonPath.path) else {
            throw ServerError.setupRequired
        }

        // Build command
        // Using the venv's Python to run mlx_audio.server
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        // Set working directory to support directory (writable location)
        // This prevents "Read-only file system" errors when server tries to create logs/
        process.currentDirectoryURL = Constants.supportDirectory

        // Create logs directory in support directory
        let logsDir = Constants.supportDirectory.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Note: model is not passed at startup - it's sent via WebSocket config
        // This allows dynamic model switching without server restart
        process.arguments = [
            "-c",
            """
            source "\(Constants.Setup.venvPath.path)/bin/activate" && \
            python -m mlx_audio.server --host \(Constants.Server.host) --port \(Constants.Server.port) --log-dir "\(logsDir.path)"
            """
        ]

        // Capture output
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        // Log server output in background
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { @MainActor in
                    Log.server.info(message)
                }
            }
        }

        self.process = process
        self.outputPipe = outputPipe

        // Start process
        do {
            try process.run()
            isRunning = true
            Log.server.info("Server process started, will load model '\(model)' on first connection (PID: \(process.processIdentifier))")
        } catch {
            throw ServerError.failedToStart(error.localizedDescription)
        }

        // Wait for server to be ready
        try await waitForServerReady()

        // Start health monitoring
        startHealthMonitoring()
    }
    
    /// Stop the server subprocess
    func stop() {
        stopHealthMonitoring()
        
        guard let process = process, process.isRunning else {
            isRunning = false
            return
        }
        
        // Send SIGTERM for graceful shutdown
        process.terminate()
        
        // Give it a moment to shut down
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            if process.isRunning {
                // Force kill if still running
                process.interrupt()
            }
            self?.cleanup()
        }
        
        isRunning = false
        Log.server.info("Server stopped")
    }

    /// Stop the server subprocess and wait for termination (best-effort).
    /// Intended for app shutdown to avoid leaving orphaned processes.
    func stopAndWait(timeout: TimeInterval) async {
        stopHealthMonitoring()

        guard let process = process, process.isRunning else {
            isRunning = false
            cleanup()
            return
        }

        Log.server.info("Stopping server process (PID: \(process.processIdentifier))")
        process.terminate()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        }

        if process.isRunning {
            Log.server.warning("Server did not terminate within \(timeout)s, interrupting...")
            process.interrupt()
        }

        cleanup()
        isRunning = false
        Log.server.info("Server stopped")
    }
    
    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
    }
    
    // MARK: - Health Monitoring
    
    private func waitForServerReady() async throws {
        let startTime = Date()
        let timeout = Constants.Server.startupTimeout
        
        while Date().timeIntervalSince(startTime) < timeout {
            if await checkHealth() {
                Log.server.info("Server is ready")
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }
        
        throw ServerError.startupTimeout
    }
    
    private func startHealthMonitoring() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: Constants.Server.healthCheckInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                if await self.checkHealth() == false {
                    await MainActor.run {
                        Log.server.warning("Health check failed")
                        self.isRunning = false
                    }
                }
            }
        }
    }
    
    private func stopHealthMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }
    
    /// Check if server is responding to health endpoint
    func checkHealth() async -> Bool {
        do {
            let (_, response) = try await URLSession.shared.data(from: Constants.Server.healthURL)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Server not responding
        }
        return false
    }

    // MARK: - Model Management

    /// Check if a model exists in the local cache
    func checkModelExists(_ modelIdentifier: String) async throws -> Bool {
        // Check in the HuggingFace cache directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let cacheDir = homeDir.appendingPathComponent(".cache/huggingface/hub")

        // Convert model ID to cache directory format
        // e.g., "mlx-community/parakeet-tdt-0.6b-v2" -> "models--mlx-community--parakeet-tdt-0.6b-v2"
        let modelPath = "models--" + modelIdentifier.replacingOccurrences(of: "/", with: "--")
        let fullPath = cacheDir.appendingPathComponent(modelPath)

        return FileManager.default.fileExists(atPath: fullPath.path)
    }

    /// Download and cache a model using the existing Python environment
    func downloadModel(_ modelIdentifier: String, progressHandler: ((Double) -> Void)? = nil) async throws {
        guard FileManager.default.fileExists(atPath: Constants.Setup.pythonPath.path) else {
            throw ServerError.setupRequired
        }

        let command = """
        source "\(Constants.Setup.venvPath.path)/bin/activate" && \
        python -c "from mlx_audio.utils import load_model; load_model('\(modelIdentifier)')"
        """

        var lastProgress: Double = 0
        let percentRegex = try? NSRegularExpression(pattern: "(\\d{1,3})(?:\\.\\d+)?%")

        try await ShellCommandRunner.run(command: command, currentDirectory: Constants.supportDirectory) { output in
            Task { @MainActor in
                Log.server.info(output)
            }

            guard let percentRegex else { return }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            let matches = percentRegex.matches(in: output, range: range)
            guard let match = matches.last, match.numberOfRanges >= 2,
                  let percentRange = Range(match.range(at: 1), in: output),
                  let percentValue = Double(output[percentRange]) else { return }

            let clamped = max(0, min(100, percentValue))
            let progress = clamped / 100.0
            if progress > lastProgress {
                lastProgress = progress
                progressHandler?(progress)
            }
        }
    }
}

extension ServerManager: ServerManaging {}

// MARK: - Server Errors

enum ServerError: LocalizedError {
    case alreadyRunning
    case setupRequired
    case failedToStart(String)
    case startupTimeout
    case healthCheckFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Server is already running"
        case .setupRequired:
            return "Python environment not set up. Please run setup first."
        case .failedToStart(let reason):
            return "Failed to start server: \(reason)"
        case .startupTimeout:
            return "Server did not start within timeout period"
        case .healthCheckFailed:
            return "Server health check failed"
        }
    }
}
