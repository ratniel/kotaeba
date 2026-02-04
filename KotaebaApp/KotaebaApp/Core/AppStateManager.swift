import Foundation
import Combine
import AppKit

/// Central state manager that orchestrates all app components
///
/// AppStateManager is a singleton that:
/// - Manages app state transitions
/// - Coordinates server, audio, websocket, and text insertion
/// - Handles hotkey events
/// - Tracks statistics
@MainActor
class AppStateManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AppStateManager()
    
    // MARK: - Published State
    
    @Published private(set) var state: AppState = .idle
    @Published private(set) var currentTranscription: String = ""
    @Published private(set) var audioAmplitude: Float = 0.0
    @Published private(set) var lastInsertionError: String?
    @Published private(set) var lastInsertionMethod: String?
    @Published var recordingMode: RecordingMode = .hold
    @Published var selectedModel: Constants.Models.Model = Constants.Models.defaultModel
    @Published private(set) var modelDownloadStatus: ModelDownloadStatus = .unknown
    @Published private(set) var modelDownloadError: String?
    @Published private(set) var modelDownloadProgress: Double?
    
    // MARK: - Components
    
    private var serverManager: ServerManager?
    private var audioCapture: AudioCaptureManager?
    private var webSocketClient: WebSocketClient?
    private var hotkeyManager: HotkeyManager?
    private var textInserter: TextInserter?
    private var statisticsManager: StatisticsManager?
    
    // MARK: - Session Tracking
    
    private var sessionStartTime: Date?
    private var sessionWordCount: Int = 0
    
    // MARK: - Initialization

    private init() {
        loadPreferences()
        setupComponents()

        // Auto-start server on app launch for instant hotkey response
        Task {
            await autoStartServer()
        }
    }
    
    private func loadPreferences() {
        if let modeString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.recordingMode),
           let mode = RecordingMode(rawValue: modeString) {
            recordingMode = mode
        }

        // Load selected model
        if let modelId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.selectedModel),
           let model = Constants.Models.availableModels.first(where: { $0.identifier == modelId }) {
            selectedModel = model
        }
    }
    
    private func setupComponents() {
        serverManager = ServerManager()
        audioCapture = AudioCaptureManager()
        textInserter = TextInserter()
        statisticsManager = StatisticsManager()
        
        // Set up delegates
        audioCapture?.delegate = self
    }
    
    // MARK: - Hotkey Initialization
    
    func initializeHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager?.delegate = self
        hotkeyManager?.recordingMode = recordingMode
        
        if hotkeyManager?.start() == true {
            Log.hotkey.info("Hotkey manager started")
        } else {
            Log.hotkey.error("Failed to start hotkey manager - check Accessibility permissions")
        }
    }
    
    // MARK: - Server Management

    /// Auto-start server on app launch if preferences allow
    private func autoStartServer() async {
        // Default to true if not explicitly set (first launch)
        let hasPreference = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.autoStartServer) != nil
        let autoStart = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoStartServer)

        await checkModelDownloadStatus()
        await ensureDefaultModelDownloadedIfNeeded()

        if !hasPreference || autoStart {
            Log.app.info("Auto-starting server on launch...")
            await startServer()
        }
    }

    func startServer() async {
        guard state == .idle || state == .error("") else { return }

        state = .serverStarting

        do {
            // Start server with selected model pre-loaded
            try await serverManager?.start(model: selectedModel.identifier)
            state = .serverRunning
            Log.server.info("Server started successfully with model: \(selectedModel.name)")
        } catch {
            state = .error(error.localizedDescription)
            Log.server.error("Server failed to start: \(error)")
        }
    }
    
    func stopServer() {
        webSocketClient?.disconnect()
        audioCapture?.stopRecording()
        serverManager?.stop()
        state = .idle
        Log.server.info("Server stopped")
    }
    
    // MARK: - Recording Control
    
    func startRecording() {
        guard state == .serverRunning else {
            Log.app.warning("Cannot start recording - server not running")
            return
        }
        
        state = .connecting
        currentTranscription = ""
        sessionWordCount = 0
        sessionStartTime = Date()
        
        // Connect WebSocket
        webSocketClient = WebSocketClient(serverURL: Constants.Server.websocketURL)
        webSocketClient?.delegate = self
        webSocketClient?.connect()
    }
    
    func stopRecording() {
        guard state == .recording || state == .connecting else { return }
        
        // Stop audio first
        audioCapture?.stopRecording()
        
        // Disconnect WebSocket
        webSocketClient?.disconnect()
        webSocketClient = nil
        
        // Save session statistics
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            statisticsManager?.recordSession(
                wordCount: sessionWordCount,
                duration: duration
            )
        }
        
        // Reset
        sessionStartTime = nil
        currentTranscription = ""
        audioAmplitude = 0.0
        
        state = .serverRunning
        Log.app.info("Recording stopped")
    }
    
    func toggleRecording() {
        if state == .recording || state == .connecting {
            stopRecording()
        } else if state == .serverRunning {
            startRecording()
        }
    }
    
    // MARK: - Transcription Handling
    
    private func handleTranscription(_ text: String, isPartial: Bool) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            Log.app.warning("Received empty transcription, ignoring")
            return
        }
        
        Log.app.info("Received transcription: \"\(trimmedText)\" (partial: \(isPartial))")
        
        // Update displayed transcription
        currentTranscription = trimmedText
        
        // For incremental insertion mode: insert each transcription as it arrives
        // The server sends transcription after each speech pause (via VAD)
        if !isPartial {
            // Count words
            let wordCount = trimmedText.split(separator: " ").count
            sessionWordCount += wordCount
            
            Log.textInsertion.info("Attempting to insert text: \"\(trimmedText)\" (\(wordCount) words)")
            
            // Insert text at cursor
            if let inserter = textInserter {
                performInsertion(text: trimmedText + " ", inserter: inserter)
            } else {
                Log.textInsertion.error("TextInserter is nil. Cannot insert text.")
                lastInsertionError = "Text inserter not initialized."
                lastInsertionMethod = nil
            }
        } else {
            Log.app.debug("Partial transcription received, waiting for final...")
        }
    }

    func testInsertion(_ text: String) {
        guard let inserter = textInserter else {
            Log.textInsertion.error("TextInserter is nil. Cannot insert text.")
            lastInsertionError = "Text inserter not initialized."
            lastInsertionMethod = nil
            return
        }
        performInsertion(text: text, inserter: inserter)
    }

    private func performInsertion(text: String, inserter: TextInserter) {
        let result = inserter.insertText(text)
        switch result {
        case .success(let method):
            lastInsertionError = nil
            lastInsertionMethod = method.rawValue
            Log.textInsertion.info("Text insertion succeeded via \(method.rawValue)")
        case .failure(let error):
            lastInsertionError = error.localizedDescription
            lastInsertionMethod = nil
            Log.textInsertion.error("Text insertion failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Model Management

    func checkModelDownloadStatus() async {
        if modelDownloadStatus == .downloading {
            return
        }

        modelDownloadStatus = .checking

        do {
            let isDownloaded = try await serverManager?.checkModelExists(selectedModel.identifier) ?? false
            modelDownloadStatus = isDownloaded ? .downloaded : .notDownloaded
            modelDownloadError = nil
            modelDownloadProgress = nil
        } catch {
            Log.server.error("Failed to check model status: \(error)")
            modelDownloadStatus = .unknown
            modelDownloadError = error.localizedDescription
            modelDownloadProgress = nil
        }
    }

    func setSelectedModel(_ model: Constants.Models.Model) async {
        selectedModel = model
        UserDefaults.standard.set(model.identifier, forKey: Constants.UserDefaultsKeys.selectedModel)

        // Check if model is downloaded
        await checkModelDownloadStatus()

        // If server is running, restart with new model
        if state == .serverRunning {
            Log.server.info("Restarting server with new model: \(model.name)")
            stopServer()
            await startServer()
        }
    }

    private func ensureDefaultModelDownloadedIfNeeded() async {
        guard SetupManager.isSetupComplete else { return }
        guard selectedModel.identifier == Constants.Models.defaultModel.identifier else { return }
        guard modelDownloadStatus == .notDownloaded || modelDownloadStatus == .unknown else { return }
        let didAutoDownload = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.didAutoDownloadDefaultModel)
        guard !didAutoDownload else { return }

        await downloadSelectedModel()
    }

    func downloadSelectedModel() async {
        guard modelDownloadStatus != .downloading else { return }
        guard SetupManager.isSetupComplete else {
            modelDownloadError = "Setup not complete. Finish setup before downloading models."
            return
        }
        guard let serverManager else {
            modelDownloadStatus = .unknown
            modelDownloadError = "Server manager unavailable."
            return
        }

        modelDownloadStatus = .downloading
        modelDownloadError = nil
        modelDownloadProgress = nil

        do {
            try await serverManager.downloadModel(selectedModel.identifier) { progress in
                Task { @MainActor in
                    self.modelDownloadProgress = progress
                }
            }
            modelDownloadStatus = .downloaded
            modelDownloadError = nil
            modelDownloadProgress = nil

            if selectedModel.identifier == Constants.Models.defaultModel.identifier {
                UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.didAutoDownloadDefaultModel)
            }
        } catch {
            Log.server.error("Failed to download model \(selectedModel.identifier): \(error)")
            modelDownloadStatus = .notDownloaded
            modelDownloadError = error.localizedDescription
            modelDownloadProgress = nil
        }
    }

    // MARK: - Preferences

    func setRecordingMode(_ mode: RecordingMode) {
        recordingMode = mode
        hotkeyManager?.recordingMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Constants.UserDefaultsKeys.recordingMode)
    }
    
    // MARK: - Shutdown
    
    func shutdown() {
        stopRecording()
        stopServer()
        hotkeyManager?.stop()
    }
}

// MARK: - WebSocketClientDelegate

extension AppStateManager: WebSocketClientDelegate {
    
    nonisolated func webSocketDidConnect() {
        Task { @MainActor in
            Log.websocket.info("WebSocket connected, starting audio...")

            // Send configuration with selected model
            let config = ClientConfig.with(model: selectedModel.identifier)
            webSocketClient?.sendConfiguration(config)

            // Start audio capture
            do {
                try audioCapture?.startRecording()
                state = .recording
            } catch {
                Log.audio.error("Failed to start audio: \(error)")
                state = .error(error.localizedDescription)
                webSocketClient?.disconnect()
            }
        }
    }
    
    nonisolated func webSocketDidDisconnect(error: Error?) {
        Task { @MainActor in
            audioCapture?.stopRecording()
            if state == .recording || state == .connecting {
                if let error = error {
                    Log.websocket.error("WebSocket disconnected with error: \(error)")
                }
                state = .serverRunning
            }
        }
    }
    
    nonisolated func webSocketDidReceiveTranscription(_ transcription: ServerTranscription) {
        Task { @MainActor in
            handleTranscription(transcription.text, isPartial: transcription.isPartial)
        }
    }
    
    nonisolated func webSocketDidReceiveStatus(_ status: ServerStatus) {
        Task { @MainActor in
            Log.server.info("Server status: \(status.status) - \(status.message)")
        }
    }
}

// MARK: - AudioCaptureDelegate

extension AppStateManager: AudioCaptureDelegate {
    
    nonisolated func audioCaptureDidReceiveBuffer(_ buffer: Data) {
        Task { @MainActor in
            webSocketClient?.sendAudioData(buffer)
        }
    }
    
    nonisolated func audioCaptureDidUpdateAmplitude(_ amplitude: Float) {
        Task { @MainActor in
            audioAmplitude = amplitude
        }
    }
    
    nonisolated func audioCaptureDidFail(error: Error) {
        Task { @MainActor in
            Log.audio.error("Audio capture failed: \(error)")
            state = .error(error.localizedDescription)
            webSocketClient?.disconnect()
        }
    }
}

// MARK: - HotkeyManagerDelegate

extension AppStateManager: HotkeyManagerDelegate {
    
    nonisolated func hotkeyDidTriggerStart() {
        Task { @MainActor in
            if recordingMode == .toggle {
                toggleRecording()
            } else {
                startRecording()
            }
        }
    }
    
    nonisolated func hotkeyDidTriggerStop() {
        Task { @MainActor in
            if recordingMode == .hold {
                stopRecording()
            }
            // In toggle mode, stop is handled by hotkeyDidTriggerStart
        }
    }
}
