import Darwin
import Foundation

typealias ServerStartupProgressHandler = (ServerStartupStage) -> Void

protocol ServerManaging: AnyObject {
    var unexpectedExitHandler: (@MainActor (String) -> Void)? { get set }
    func start(model: String, progressHandler: ServerStartupProgressHandler?) async throws
    func stop()
    func stopAndWait(timeout: TimeInterval) async
    func inspectRecoverablePortConflict() async throws -> ServerPortConflict?
    func terminateRecoverablePortConflict() async throws -> ServerPortConflict
    func checkModelExists(_ modelIdentifier: String) async throws -> Bool
    func validateModelCompatibility(_ modelIdentifier: String) async throws
    func downloadModel(_ modelIdentifier: String, progressHandler: ((Double) -> Void)?) async throws
}

/// Manages the mlx_audio.server Python subprocess
///
/// Responsibilities:
/// - Start/stop the server process
/// - Monitor server health
/// - Capture server output for logging
class ServerManager {
    private enum RecoveryTiming {
        static let gracefulTerminationTimeout: TimeInterval = 2.0
        static let forceKillTimeout: TimeInterval = 1.0
        static let processPollIntervalNanoseconds: UInt64 = 100_000_000
    }
    
    // MARK: - Properties
    
    private var process: Process?
    private var processGroupID: pid_t?
    private var outputPipe: Pipe?
    private var healthCheckTimer: Timer?
    private let serverMetadataURL = Constants.supportDirectory.appendingPathComponent("server-process.json")
    private var isStopping = false
    
    var unexpectedExitHandler: (@MainActor (String) -> Void)?
    private(set) var isRunning = false
    
    // MARK: - Server Control

    /// Start the mlx_audio.server subprocess
    /// Runs a startup-time model validation before launching the server so model
    /// failures are discovered before the first hotkey/WebSocket session.
    func start(model: String, progressHandler: ServerStartupProgressHandler? = nil) async throws {
        guard !isRunning else {
            throw ServerError.alreadyRunning
        }

        isStopping = false
        await MainActor.run {
            progressHandler?(.preparingRuntime)
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
                "Another server is already listening on \(Constants.Server.host):\(Constants.Server.port). Stop the stale Kotaeba/MLX server process and try again.",
                nil
            )
        }

        guard let pythonURL = Constants.Setup.pythonPath else {
            throw ServerError.setupRequired
        }

        await MainActor.run {
            progressHandler?(.validatingModel)
        }
        try await validateModelStartup(modelIdentifier: model, pythonURL: pythonURL)

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
            await MainActor.run {
                progressHandler?(.launchingServer)
            }
            try process.run()
            let processID = process.processIdentifier
            let isolatedGroupID = await resolveTrackedProcessGroup(for: processID)
            isRunning = true
            processGroupID = isolatedGroupID
            try persistServerMetadata(
                processID: processID,
                processGroupID: isolatedGroupID,
                pythonURL: pythonURL,
                logDirectory: logsDir
            )
            let trackingDescription: String
            if let isolatedGroupID {
                trackingDescription = "PID: \(processID), PGID: \(isolatedGroupID)"
            } else {
                trackingDescription = "PID: \(processID), process-only tracking"
            }
            Log.server.info(
                "Server process started after validating model '\(model)' (\(trackingDescription))"
            )
        } catch {
            terminateTrackedServer(force: true)
            cleanup()
            throw ServerError.failedToStart(error.localizedDescription, nil)
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
        isStopping = true
        
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
        isStopping = true

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

    func inspectRecoverablePortConflict() async throws -> ServerPortConflict? {
        guard await checkHealth() else {
            return nil
        }

        let processes = try await recoverableOwnedServerProcessesOnConfiguredPort()
        guard !processes.isEmpty else {
            return nil
        }

        return ServerPortConflict(
            host: Constants.Server.host,
            port: Constants.Server.port,
            processes: processes.map {
                ServerPortConflictProcess(
                    processID: $0.processID,
                    parentProcessID: $0.parentProcessID,
                    processGroupID: $0.processGroupID,
                    command: $0.command
                )
            }
        )
    }

    func terminateRecoverablePortConflict() async throws -> ServerPortConflict {
        guard let conflict = try await inspectRecoverablePortConflict() else {
            throw ServerError.portConflictRecoveryUnavailable
        }

        let safeProcessGroupIDs = Set(conflict.processes.map(\.processGroupID).filter { $0 > 1 })
        guard !safeProcessGroupIDs.isEmpty else {
            Log.server.error(
                "Refusing to terminate recoverable port conflict on \(conflict.host):\(conflict.port) because no safe process groups were found"
            )
            throw ServerError.failedToStart(
                "Kotaeba detected an existing server on \(conflict.host):\(conflict.port), but could not safely stop it automatically. Close it manually, then try again.",
                nil
            )
        }

        Log.server.warning(
            "Terminating recoverable Kotaeba server conflict on \(conflict.host):\(conflict.port) for PIDs \(conflict.processIDList)"
        )

        for processGroupID in safeProcessGroupIDs {
            _ = killpg(processGroupID, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(RecoveryTiming.gracefulTerminationTimeout)
        while safeProcessGroupIDs.contains(where: isProcessGroupActive) && Date() < deadline {
            try? await Task.sleep(nanoseconds: RecoveryTiming.processPollIntervalNanoseconds)
        }

        let remainingGroupIDs = safeProcessGroupIDs.filter(isProcessGroupActive)
        if !remainingGroupIDs.isEmpty {
            Log.server.warning(
                "Recoverable conflict ignored SIGTERM for groups \(remainingGroupIDs.map(String.init).joined(separator: ", ")); sending SIGKILL"
            )
            for processGroupID in remainingGroupIDs {
                _ = killpg(processGroupID, SIGKILL)
            }

            let forceKillDeadline = Date().addingTimeInterval(RecoveryTiming.forceKillTimeout)
            while remainingGroupIDs.contains(where: isProcessGroupActive) && Date() < forceKillDeadline {
                try? await Task.sleep(nanoseconds: RecoveryTiming.processPollIntervalNanoseconds)
            }
        }

        if await checkHealth() {
            throw ServerError.failedToStart(
                "Kotaeba could not stop the existing server on \(conflict.host):\(conflict.port). Close it manually, then try again.",
                nil
            )
        }

        clearServerMetadata()
        return conflict
    }
    
    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        processGroupID = nil
        isRunning = false
        isStopping = false
        clearServerMetadata()
    }
    
    // MARK: - Health Monitoring
    
    private func waitForServerReady(process: Process) async throws {
        let startTime = Date()
        let timeout = Constants.Server.startupTimeout
        
        while Date().timeIntervalSince(startTime) < timeout {
            guard process.isRunning else {
                throw ServerError.failedToStart(
                    "Server process exited before becoming ready. Check for a port conflict or runtime startup error.",
                    nil
                )
            }

            if await checkHealth() {
                // Give the launched process a brief moment to prove that it is
                // the one that actually stayed alive after binding the port.
                try await Task.sleep(nanoseconds: 300_000_000)
                guard process.isRunning else {
                    throw ServerError.failedToStart(
                        "Server process exited after startup. Another process may already be using \(Constants.Server.host):\(Constants.Server.port).",
                        nil
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
        let launcher = """
        import os,sys
        try:
            os.setsid()
        except PermissionError:
            pass
        os.execve(sys.executable, [sys.executable, '-m', 'mlx_audio.server', *sys.argv[1:]], os.environ)
        """

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

    private func resolveTrackedProcessGroup(for processID: pid_t) async -> pid_t? {
        let deadline = Date().addingTimeInterval(2.0)
        var inheritedGroupObservations = 0

        while Date() < deadline {
            let groupID = getpgid(processID)
            if groupID == processID {
                return groupID
            }

            if groupID == -1 {
                return nil
            }

            if groupID > 0 {
                inheritedGroupObservations += 1
                if inheritedGroupObservations >= 3 {
                    Log.server.warning(
                        "Dedicated server process group unavailable; using process-only tracking for PID \(processID)"
                    )
                    return nil
                }
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        Log.server.warning(
            "Timed out waiting for a dedicated server process group; using process-only tracking for PID \(processID)"
        )
        return nil
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

    private func isProcessActive(_ processID: pid_t) -> Bool {
        if kill(processID, 0) == 0 {
            return true
        }

        return errno == EPERM
    }

    private func persistServerMetadata(
        processID: pid_t,
        processGroupID: pid_t?,
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

        let ownedProcesses = try await ownedProcessesForCurrentMetadata(metadata)
        guard !ownedProcesses.isEmpty else {
            clearServerMetadata()
            return
        }

        let trackingDescription = metadata.processGroupID.map { "PGID \($0)" } ?? "PID \(metadata.processID)"
        Log.server.warning(
            "Found stale app-owned MLX server processes for \(trackingDescription); cleaning them up before launch"
        )

        if let processGroupID = metadata.processGroupID {
            _ = killpg(processGroupID, SIGTERM)
            let deadline = Date().addingTimeInterval(2.0)
            while isProcessGroupActive(processGroupID) && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            if isProcessGroupActive(processGroupID) {
                Log.server.warning("Stale server group \(processGroupID) ignored SIGTERM, sending SIGKILL")
                _ = killpg(processGroupID, SIGKILL)
                let forceKillDeadline = Date().addingTimeInterval(1.0)
                while isProcessGroupActive(processGroupID) && Date() < forceKillDeadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        } else {
            for ownedProcess in ownedProcesses {
                _ = kill(ownedProcess.processID, SIGTERM)
            }

            let deadline = Date().addingTimeInterval(2.0)
            while ownedProcesses.contains(where: { isProcessActive($0.processID) }) && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            let remainingProcesses = ownedProcesses.filter { isProcessActive($0.processID) }
            if !remainingProcesses.isEmpty {
                Log.server.warning("Stale server processes ignored SIGTERM, sending SIGKILL")
                for ownedProcess in remainingProcesses {
                    _ = kill(ownedProcess.processID, SIGKILL)
                }

                let forceKillDeadline = Date().addingTimeInterval(1.0)
                while remainingProcesses.contains(where: { isProcessActive($0.processID) }) && Date() < forceKillDeadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }

        clearServerMetadata()
    }

    private func ownedProcessesForCurrentMetadata(_ metadata: OwnedServerMetadata) async throws -> [ProcessSnapshot] {
        try await listProcesses().filter { snapshot in
            let commandMatches =
                snapshot.command.contains(metadata.pythonPath) &&
                snapshot.command.contains("mlx_audio.server") &&
                snapshot.command.contains(metadata.logDirectory) &&
                snapshot.command.contains("--port \(metadata.port)")

            guard commandMatches else { return false }

            if let processGroupID = metadata.processGroupID {
                return snapshot.processGroupID == processGroupID
            }

            return snapshot.processID == metadata.processID
        }
    }

    private func recoverableOwnedServerProcessesOnConfiguredPort() async throws -> [ProcessSnapshot] {
        let logDirectory = Constants.supportDirectory.appendingPathComponent("logs").path
        let runtimeHints = [
            Constants.supportDirectory.path,
            Constants.Setup.expectedBundledRuntimeLocation.path,
            Constants.Setup.bundledRuntimeProjectLocation.path,
            Constants.Setup.pythonPath?.deletingLastPathComponent().deletingLastPathComponent().path
        ].compactMap { $0 }

        return try await listProcesses().filter { snapshot in
            guard snapshot.command.contains("mlx_audio.server"),
                  snapshot.command.contains("--port \(Constants.Server.port)"),
                  snapshot.command.contains(logDirectory) else {
                return false
            }

            return runtimeHints.contains(where: { snapshot.command.contains($0) })
        }
    }

    private func listProcesses() async throws -> [ProcessSnapshot] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try self.listProcessesSynchronously())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func listProcessesSynchronously() throws -> [ProcessSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,pgid=,command="]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServerError.failedToStart("Unable to inspect running processes for stale server cleanup.", nil)
        }

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
                        self.handleUnexpectedExit(
                            "Server stopped responding on \(Constants.Server.host):\(Constants.Server.port)."
                        )
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
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.canConnectToServerPort())
            }
        }
    }

    private func handleUnexpectedExit(_ reason: String) {
        guard !isStopping else { return }
        guard isRunning || process != nil || processGroupID != nil else { return }

        stopHealthMonitoring()
        Log.server.warning(reason)
        cleanup()

        unexpectedExitHandler?(reason)
    }

    private func canConnectToServerPort() -> Bool {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var info: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(Constants.Server.host, String(Constants.Server.port), &hints, &info)
        guard status == 0, let firstInfo = info else {
            return false
        }
        defer { freeaddrinfo(firstInfo) }

        var currentInfo: UnsafeMutablePointer<addrinfo>? = firstInfo
        while let addressInfo = currentInfo {
            let socketDescriptor = socket(
                addressInfo.pointee.ai_family,
                addressInfo.pointee.ai_socktype,
                addressInfo.pointee.ai_protocol
            )

            if socketDescriptor >= 0 {
                defer { close(socketDescriptor) }

                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(
                    socketDescriptor,
                    SOL_SOCKET,
                    SO_SNDTIMEO,
                    &timeout,
                    socklen_t(MemoryLayout<timeval>.size)
                )
                setsockopt(
                    socketDescriptor,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    &timeout,
                    socklen_t(MemoryLayout<timeval>.size)
                )

                if connect(socketDescriptor, addressInfo.pointee.ai_addr, addressInfo.pointee.ai_addrlen) == 0 {
                    return true
                }
            }

            currentInfo = addressInfo.pointee.ai_next
        }

        return false
    }

    private func validateModelStartup(modelIdentifier: String, pythonURL: URL) async throws {
        let command = """
        import sys, traceback
        from mlx_audio.utils import load_model

        model_id = sys.argv[1]
        try:
            load_model(model_id)
            print(f"Model validation succeeded for {model_id}")
        except Exception:
            traceback.print_exc()
            raise
        """

        do {
            try await ShellCommandRunner.run(
                executableURL: pythonURL,
                arguments: ["-c", command, modelIdentifier],
                currentDirectory: Constants.supportDirectory,
                environment: ServerEnvironment.build(model: modelIdentifier)
            ) { output in
                Log.server.info(output)
            }
        } catch let error as ShellCommandError {
            let details = error.commandOutput
            let userFacingMessage = Constants.Models
                .startupValidationMessage(for: Constants.Models.model(withIdentifier: modelIdentifier) ?? Constants.Models.defaultModel,
                                          rawError: details)
            throw ServerError.failedToStart(userFacingMessage, details)
        } catch {
            throw ServerError.failedToStart("Failed to validate \(modelIdentifier) before startup.", error.localizedDescription)
        }
    }

    // MARK: - Model Management

    /// Validate that MLX Audio can load the model before it is saved or selected.
    func validateModelCompatibility(_ modelIdentifier: String) async throws {
        guard Constants.Models.isValidIdentifier(modelIdentifier) else {
            throw ServerError.invalidModelIdentifier
        }
        guard let pythonURL = Constants.Setup.pythonPath else {
            throw ServerError.setupRequired
        }

        try await validateModelStartup(modelIdentifier: modelIdentifier, pythonURL: pythonURL)
    }

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
        let command = """
        import sys
        from mlx_audio.utils import load_model

        load_model(sys.argv[1])
        """
        try await ShellCommandRunner.run(
            executableURL: pythonURL,
            arguments: ["-c", command, modelIdentifier],
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

struct ServerPortConflict: Equatable {
    let host: String
    let port: Int
    let processes: [ServerPortConflictProcess]

    var isLikelyStale: Bool {
        processes.allSatisfy { $0.parentProcessID == 1 }
    }

    var processIDList: String {
        processes.map(\.processID).map(String.init).joined(separator: ", ")
    }

    var recoverySummary: String {
        let processLabel = processes.count == 1 ? "process" : "processes"
        let summaryPrefix: String
        if isLikelyStale {
            summaryPrefix = "Detected stale Kotaeba server \(processLabel)"
        } else {
            summaryPrefix = "Detected Kotaeba server \(processLabel) already using this port"
        }

        return "\(summaryPrefix) on \(host):\(port) (PID \(processIDList))."
    }
}

struct ServerPortConflictProcess: Equatable {
    let processID: Int32
    let parentProcessID: Int32
    let processGroupID: Int32
    let command: String
}

private struct OwnedServerMetadata: Codable {
    let processID: Int32
    let processGroupID: Int32?
    let host: String
    let port: Int
    let pythonPath: String
    let logDirectory: String
    let launchedAt: Date
}

private struct ProcessSnapshot {
    let processID: Int32
    let parentProcessID: Int32
    let processGroupID: Int32
    let command: String

    init?(rawLine: String) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(maxSplits: 3, whereSeparator: \.isWhitespace)
        guard parts.count == 4,
              let processID = Int32(parts[0]),
              let parentProcessID = Int32(parts[1]),
              let processGroupID = Int32(parts[2]) else {
            return nil
        }

        self.processID = processID
        self.parentProcessID = parentProcessID
        self.processGroupID = processGroupID
        self.command = String(parts[3])
    }
}

// MARK: - Server Errors

enum ServerError: LocalizedError {
    case alreadyRunning
    case setupRequired
    case failedToStart(String, String?)
    case startupTimeout
    case healthCheckFailed
    case invalidModelIdentifier
    case portConflictRecoveryUnavailable

    var isPortConflict: Bool {
        switch self {
        case .failedToStart(let reason, _):
            return reason.contains("already listening on") || reason.contains("already be using")
        default:
            return false
        }
    }

    var diagnosticDetails: String? {
        switch self {
        case .failedToStart(_, let details):
            return details
        default:
            return nil
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Server is already running"
        case .setupRequired:
            return "Speech runtime unavailable. Reinstall the app or restore the development runtime before continuing."
        case .failedToStart(let reason, _):
            return "Failed to start server: \(reason)"
        case .startupTimeout:
            return "Server did not start within timeout period"
        case .healthCheckFailed:
            return "Server health check failed"
        case .invalidModelIdentifier:
            return "Invalid model identifier"
        case .portConflictRecoveryUnavailable:
            return "No recoverable Kotaeba server conflict was found on the configured port"
        }
    }
}
