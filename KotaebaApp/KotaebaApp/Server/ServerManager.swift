import Darwin
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
    private var processGroupID: pid_t?
    private var outputPipe: Pipe?
    private var healthCheckTimer: Timer?
    private let serverMetadataURL = Constants.supportDirectory.appendingPathComponent("server-process.json")
    
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

        try await cleanupStaleOwnedServerIfNeeded()

        // If something is already answering on the configured port, starting a
        // second server will fail with "address already in use" and we can end
        // up talking to a stale/orphaned process instead.
        guard await checkHealth() == false else {
            throw ServerError.failedToStart(
                "Another server is already listening on \(Constants.Server.host):\(Constants.Server.port). Stop the stale Kotaeba/MLX server process and try again."
            )
        }

        guard let pythonURL = Constants.Setup.pythonPath else {
            throw ServerError.setupRequired
        }

        let process = Process()
        process.executableURL = pythonURL

        // Set working directory to support directory (writable location)
        // This prevents "Read-only file system" errors when server tries to create logs/
        process.currentDirectoryURL = Constants.supportDirectory

        // Create logs directory in support directory
        let logsDir = Constants.supportDirectory.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Launch through a tiny Python trampoline that creates a dedicated
        // session/process group before exec'ing mlx_audio.server. That gives
        // us a stable process group we can terminate as one unit on shutdown.
        process.arguments = serverLaunchArguments(logDirectory: logsDir)
        process.environment = ServerEnvironment.build(model: model)

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
            let processID = process.processIdentifier
            let isolatedGroupID = try await waitForDedicatedProcessGroup(for: processID)
            isRunning = true
            processGroupID = isolatedGroupID
            try persistServerMetadata(
                processID: processID,
                processGroupID: isolatedGroupID,
                pythonURL: pythonURL,
                logDirectory: logsDir
            )
            Log.server.info(
                "Server process started, will load model '\(model)' on first connection (PID: \(processID), PGID: \(isolatedGroupID))"
            )
        } catch {
            terminateTrackedServer(force: true)
            cleanup()
            throw ServerError.failedToStart(error.localizedDescription)
        }

        do {
            // Wait for server to be ready
            try await waitForServerReady(process: process)

            // Start health monitoring
            startHealthMonitoring()
        } catch {
            terminateTrackedServer(force: true)
            cleanup()
            throw error
        }
    }
    
    /// Stop the server subprocess
    func stop() {
        stopHealthMonitoring()
        
        guard process != nil || processGroupID != nil else {
            isRunning = false
            cleanup()
            return
        }

        terminateTrackedServer(force: false)

        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if let processGroupID = self.processGroupID, self.isProcessGroupActive(processGroupID) {
                self.terminateTrackedServer(force: true)
            }
            self.cleanup()
        }
        
        isRunning = false
        Log.server.info("Server stopped")
    }

    /// Stop the server subprocess and wait for termination (best-effort).
    /// Intended for app shutdown to avoid leaving orphaned processes.
    func stopAndWait(timeout: TimeInterval) async {
        stopHealthMonitoring()

        guard process != nil || processGroupID != nil else {
            isRunning = false
            cleanup()
            return
        }

        if let processGroupID {
            Log.server.info("Stopping server group (PGID: \(processGroupID))")
        } else if let process {
            Log.server.info("Stopping server process (PID: \(process.processIdentifier))")
        }

        terminateTrackedServer(force: false)

        let deadline = Date().addingTimeInterval(timeout)
        while isTrackedServerStillRunning() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
        }

        if isTrackedServerStillRunning() {
            Log.server.warning("Server did not terminate within \(timeout)s, force killing process group...")
            terminateTrackedServer(force: true)
            let forceKillDeadline = Date().addingTimeInterval(1.0)
            while isTrackedServerStillRunning() && Date() < forceKillDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        cleanup()
        isRunning = false
        Log.server.info("Server stopped")
    }
    
    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        processGroupID = nil
        clearServerMetadata()
    }
    
    // MARK: - Health Monitoring
    
    private func waitForServerReady(process: Process) async throws {
        let startTime = Date()
        let timeout = Constants.Server.startupTimeout
        
        while Date().timeIntervalSince(startTime) < timeout {
            guard process.isRunning else {
                throw ServerError.failedToStart(
                    "Server process exited before becoming ready. Check for a port conflict or runtime startup error."
                )
            }

            if await checkHealth() {
                // Give the launched process a brief moment to prove that it is
                // the one that actually stayed alive after binding the port.
                try await Task.sleep(nanoseconds: 300_000_000)
                guard process.isRunning else {
                    throw ServerError.failedToStart(
                        "Server process exited after startup. Another process may already be using \(Constants.Server.host):\(Constants.Server.port)."
                    )
                }
                Log.server.info("Server is ready")
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }
        
        throw ServerError.startupTimeout
    }

    private func serverLaunchArguments(logDirectory: URL) -> [String] {
        let launcher =
            "import os,sys; os.setsid(); os.execve(sys.executable, [sys.executable, '-m', 'mlx_audio.server', *sys.argv[1:]], os.environ)"

        return [
            "-c",
            launcher,
            "--host",
            Constants.Server.host,
            "--port",
            String(Constants.Server.port),
            "--log-dir",
            logDirectory.path
        ]
    }

    private func waitForDedicatedProcessGroup(for processID: pid_t) async throws -> pid_t {
        let deadline = Date().addingTimeInterval(2.0)

        while Date() < deadline {
            let groupID = getpgid(processID)
            if groupID == processID {
                return groupID
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        throw ServerError.failedToStart("Failed to verify dedicated server process group.")
    }

    private func terminateTrackedServer(force: Bool) {
        if let processGroupID {
            let signal = force ? SIGKILL : SIGTERM
            let label = force ? "SIGKILL" : "SIGTERM"
            Log.server.info("Sending \(label) to server process group \(processGroupID)")
            _ = killpg(processGroupID, signal)
            return
        }

        guard let process else { return }
        if force {
            Log.server.info("Force killing server process \(process.processIdentifier)")
            _ = kill(process.processIdentifier, SIGKILL)
        } else {
            Log.server.info("Terminating server process \(process.processIdentifier)")
            process.terminate()
        }
    }

    private func isTrackedServerStillRunning() -> Bool {
        if let processGroupID {
            return isProcessGroupActive(processGroupID)
        }

        if let process {
            return process.isRunning
        }

        return false
    }

    private func isProcessGroupActive(_ processGroupID: pid_t) -> Bool {
        if killpg(processGroupID, 0) == 0 {
            return true
        }

        return errno == EPERM
    }

    private func persistServerMetadata(
        processID: pid_t,
        processGroupID: pid_t,
        pythonURL: URL,
        logDirectory: URL
    ) throws {
        let metadata = OwnedServerMetadata(
            processID: processID,
            processGroupID: processGroupID,
            host: Constants.Server.host,
            port: Constants.Server.port,
            pythonPath: pythonURL.path,
            logDirectory: logDirectory.path,
            launchedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: serverMetadataURL, options: .atomic)
    }

    private func loadServerMetadata() -> OwnedServerMetadata? {
        guard let data = try? Data(contentsOf: serverMetadataURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OwnedServerMetadata.self, from: data)
    }

    private func clearServerMetadata() {
        try? FileManager.default.removeItem(at: serverMetadataURL)
    }

    private func cleanupStaleOwnedServerIfNeeded() async throws {
        guard let metadata = loadServerMetadata() else {
            return
        }

        let ownedProcesses = try ownedProcessesForCurrentMetadata(metadata)
        guard !ownedProcesses.isEmpty else {
            clearServerMetadata()
            return
        }

        Log.server.warning(
            "Found stale app-owned MLX server processes for PGID \(metadata.processGroupID); cleaning them up before launch"
        )

        _ = killpg(metadata.processGroupID, SIGTERM)
        let deadline = Date().addingTimeInterval(2.0)
        while isProcessGroupActive(metadata.processGroupID) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if isProcessGroupActive(metadata.processGroupID) {
            Log.server.warning("Stale server group \(metadata.processGroupID) ignored SIGTERM, sending SIGKILL")
            _ = killpg(metadata.processGroupID, SIGKILL)
            let forceKillDeadline = Date().addingTimeInterval(1.0)
            while isProcessGroupActive(metadata.processGroupID) && Date() < forceKillDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        clearServerMetadata()
    }

    private func ownedProcessesForCurrentMetadata(_ metadata: OwnedServerMetadata) throws -> [ProcessSnapshot] {
        try listProcesses().filter { snapshot in
            snapshot.processGroupID == metadata.processGroupID &&
            snapshot.command.contains(metadata.pythonPath) &&
            snapshot.command.contains("mlx_audio.server") &&
            snapshot.command.contains(metadata.logDirectory) &&
            snapshot.command.contains("--port \(metadata.port)")
        }
    }

    private func listProcesses() throws -> [ProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,pgid=,command="]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServerError.failedToStart("Unable to inspect running processes for stale server cleanup.")
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return output
            .split(separator: "\n")
            .compactMap { ProcessSnapshot(rawLine: String($0)) }
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
        guard let pythonURL = Constants.Setup.pythonPath else {
            throw ServerError.setupRequired
        }
        guard Constants.Models.availableModels.contains(where: { $0.identifier == modelIdentifier }) else {
            throw ServerError.invalidModelIdentifier
        }

        var lastProgress: Double = 0
        let percentRegex = try? NSRegularExpression(pattern: "(\\d{1,3})(?:\\.\\d+)?%")
        let command = "from mlx_audio.utils import load_model; load_model('\(modelIdentifier)')"
        try await ShellCommandRunner.run(
            executableURL: pythonURL,
            arguments: ["-c", command],
            currentDirectory: Constants.supportDirectory,
            environment: ServerEnvironment.build(model: modelIdentifier)
        ) { output in
            Log.server.info(output)

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

private struct OwnedServerMetadata: Codable {
    let processID: Int32
    let processGroupID: Int32
    let host: String
    let port: Int
    let pythonPath: String
    let logDirectory: String
    let launchedAt: Date
}

private struct ProcessSnapshot {
    let processID: Int32
    let processGroupID: Int32
    let command: String

    init?(rawLine: String) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(maxSplits: 2, whereSeparator: \.isWhitespace)
        guard parts.count == 3,
              let processID = Int32(parts[0]),
              let processGroupID = Int32(parts[1]) else {
            return nil
        }

        self.processID = processID
        self.processGroupID = processGroupID
        self.command = String(parts[2])
    }
}

// MARK: - Server Errors

enum ServerError: LocalizedError {
    case alreadyRunning
    case setupRequired
    case failedToStart(String)
    case startupTimeout
    case healthCheckFailed
    case invalidModelIdentifier
    
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Server is already running"
        case .setupRequired:
            return "Speech runtime unavailable. Reinstall the app or restore the development runtime before continuing."
        case .failedToStart(let reason):
            return "Failed to start server: \(reason)"
        case .startupTimeout:
            return "Server did not start within timeout period"
        case .healthCheckFailed:
            return "Server health check failed"
        case .invalidModelIdentifier:
            return "Invalid model identifier"
        }
    }
}
