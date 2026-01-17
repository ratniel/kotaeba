import Foundation

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
    func start() async throws {
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
        process.arguments = [
            "-c",
            """
            source "\(Constants.Setup.venvPath.path)/bin/activate" && \
            mlx_audio.server --host \(Constants.Server.host) --port \(Constants.Server.port)
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
                print("[Server] \(output)", terminator: "")
            }
        }
        
        self.process = process
        self.outputPipe = outputPipe
        
        // Start process
        do {
            try process.run()
            isRunning = true
            print("[ServerManager] Server process started (PID: \(process.processIdentifier))")
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
        print("[ServerManager] Server stopped")
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
                print("[ServerManager] Server is ready")
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
        }
        
        throw ServerError.startupTimeout
    }
    
    private func startHealthMonitoring() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: Constants.Server.healthCheckInterval, repeats: true) { [weak self] _ in
            Task {
                if await self?.checkHealth() == false {
                    print("[ServerManager] Health check failed")
                    await MainActor.run {
                        self?.isRunning = false
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
}

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
