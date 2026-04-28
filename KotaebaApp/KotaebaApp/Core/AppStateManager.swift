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
    static let testingInstance = AppStateManager(
        serverManager: ServerManager(),
        statisticsManager: StatisticsManager(storeInMemory: true),
        shouldAutoStartServer: false
    )
    
    // MARK: - Published State
    
    @Published private(set) var state: AppState = .idle
    @Published private(set) var currentTranscription: String = ""
    @Published private(set) var audioAmplitude: Float = 0.0
    @Published private(set) var lastInsertionError: String?
    @Published private(set) var lastInsertionMethod: String?
    @Published private(set) var lastCompletedTranscription: String?
    @Published private(set) var permissionStatus: PermissionStatus = PermissionManager.getPermissionStatus(source: "initial")
    @Published private(set) var isHotkeyActive = false
    @Published private(set) var hotkeyStatusMessage = "Hotkey not initialized"
    @Published private(set) var recordingModePromptMessage: String?
    @Published private(set) var currentHotkey: HotkeyShortcut = .default
    @Published var recordingMode: RecordingMode = .hold
    @Published var selectedModel: Constants.Models.Model = Constants.Models.defaultModel
    @Published private(set) var modelDownloadStatus: ModelDownloadStatus = .unknown
    @Published private(set) var modelDownloadError: String?
    @Published private(set) var modelDownloadProgress: Double?
    @Published private(set) var lastDiagnosticErrorDetails: String?
    @Published private(set) var serverStartupStage: ServerStartupStage?
    @Published private(set) var aggregatedStats: AggregatedStats = .empty
    @Published private(set) var todayStats: AggregatedStats = .empty
    @Published private(set) var audioInputDevices: [AudioInputDevice] = [.systemDefault]
    @Published private(set) var selectedAudioInputDeviceID = AudioInputDevice.systemDefaultID
    
    // MARK: - Components
    
    private var serverManager: ServerManaging?
    private var audioCapture: (any AudioCapturing)?
    private var webSocketClient: WebSocketClient?
    private var hotkeyManager: HotkeyManager?
    private var textInserter: TextInserter?
    private let statisticsManager: any StatisticsManaging
    private var permissionRefreshTask: Task<Void, Never>?
    private var pendingWebSocketDisconnectTask: Task<Void, Never>?
    private var activeAudioSessionID: AudioCaptureSessionID?
    
    // MARK: - Session Tracking
    
    private var sessionStartTime: Date?
    private var sessionWordCount: Int = 0
    
    // MARK: - Initialization

    private init() {
        self.statisticsManager = StatisticsManager.shared
        loadPreferences()
        setupComponents()
        refreshStatistics()

        // Auto-start server on app launch for instant hotkey response
        if !Constants.isRunningTests {
            Task {
                await autoStartServer()
            }
        }
    }

    init(
        serverManager: ServerManaging,
        audioCapture: (any AudioCapturing)? = nil,
        textInserter: TextInserter? = nil,
        statisticsManager: (any StatisticsManaging)? = nil,
        shouldAutoStartServer: Bool = false
    ) {
        self.statisticsManager = statisticsManager ?? StatisticsManager.shared
        self.serverManager = serverManager
        self.audioCapture = audioCapture
        self.textInserter = textInserter
        loadPreferences()
        refreshStatistics()
        self.audioCapture?.delegate = self
        configureServerCallbacks()
        configureAudioCallbacks()
        refreshAudioInputDevices()

        if shouldAutoStartServer && !Constants.isRunningTests {
            Task {
                await self.autoStartServer()
            }
        }
    }
    
    private func loadPreferences() {
        UserDefaults.standard.register(defaults: [
            Constants.UserDefaultsKeys.safeModeEnabled: true,
            Constants.UserDefaultsKeys.serverHost: Constants.Server.defaultHost,
            Constants.UserDefaultsKeys.serverPort: Constants.Server.defaultPort,
            Constants.UserDefaultsKeys.selectedAudioDevice: AudioInputDevice.systemDefaultID
        ])
        SettingsMigration.migrateIfNeeded()
        currentHotkey = HotkeyShortcutStore.load()

        if let modeString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.recordingMode),
           let mode = RecordingMode(rawValue: modeString) {
            recordingMode = mode
        }

        // Load selected model
        if let modelId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.selectedModel) {
            if let model = Constants.Models.model(withIdentifier: modelId) {
                selectedModel = model
            } else {
                selectedModel = Constants.Models.defaultModel
                UserDefaults.standard.set(Constants.Models.defaultModel.identifier, forKey: Constants.UserDefaultsKeys.selectedModel)
            }
        }
    }
    
    private func setupComponents() {
        serverManager = ServerManager()
        audioCapture = AudioCaptureManager()
        textInserter = TextInserter()
        // Set up delegates
        audioCapture?.delegate = self
        configureServerCallbacks()
        configureAudioCallbacks()
        refreshAudioInputDevices()
    }

    private func configureServerCallbacks() {
        serverManager?.unexpectedExitHandler = { [weak self] reason in
            self?.handleUnexpectedServerExit(reason: reason)
        }
    }

    private func configureAudioCallbacks() {
        audioCapture?.inputDevicesDidChange = { [weak self] in
            Task { @MainActor in
                self?.refreshAudioInputDevices()
            }
        }
    }

    private func handleUnexpectedServerExit(reason: String) {
        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
        stopAudioCapture()
        webSocketClient?.disconnect()
        webSocketClient = nil
        state = .error(reason)
    }
    
    // MARK: - Hotkey Initialization

    func refreshPermissionStatus(source: String = "manual") {
        let latestStatus = PermissionManager.getPermissionStatus(source: source)
        guard latestStatus != permissionStatus else { return }
        permissionStatus = latestStatus
    }

    @discardableResult
    func initializeHotkey(promptIfMissing: Bool = false) -> Bool {
        refreshPermissionStatus(source: "initializeHotkey")

        if hotkeyManager == nil {
            hotkeyManager = HotkeyManager(shortcut: currentHotkey)
            hotkeyManager?.delegate = self
        }

        hotkeyManager?.recordingMode = recordingMode
        hotkeyManager?.setHotkey(currentHotkey)

        if hotkeyManager?.start(promptIfMissing: promptIfMissing) == true {
            isHotkeyActive = true
            hotkeyStatusMessage = "Hotkey listener active"
            Log.hotkey.info("Hotkey manager started")
            return true
        }

        isHotkeyActive = false
        hotkeyStatusMessage = permissionStatus.accessibility
            ? "Hotkey listener failed to start"
            : "Accessibility permission is required"
        Log.hotkey.error("Failed to start hotkey manager - check Accessibility permissions")
        return false
    }

    func requestAccessibilityPermission() {
        _ = PermissionManager.requestAccessibilityPermission()
        refreshPermissionStatus(source: "requestAccessibilityPermission")
    }

    func handleApplicationDidBecomeActive() {
        let previousStatus = permissionStatus
        refreshPermissionStatus(source: "didBecomeActive")

        if permissionStatus.accessibility {
            if !previousStatus.accessibility {
                Log.permissions.info("Accessibility granted while app was inactive; retrying hotkey initialization")
            }
            _ = initializeHotkey(promptIfMissing: false)
        } else if isHotkeyActive {
            hotkeyManager?.stop()
            isHotkeyActive = false
            hotkeyStatusMessage = "Accessibility permission is required"
        }
    }

    func refreshPermissionsAndHotkey(promptIfMissing: Bool = false) {
        refreshPermissionStatus(source: "refreshPermissionsAndHotkey")

        guard permissionStatus.accessibility else {
            isHotkeyActive = false
            hotkeyStatusMessage = "Accessibility permission is required"
            if promptIfMissing {
                requestAccessibilityPermission()
            }
            return
        }

        _ = initializeHotkey(promptIfMissing: false)
    }

    @discardableResult
    func suspendHotkeyForShortcutCapture() -> Bool {
        let shouldRestore = isHotkeyActive
        guard shouldRestore else { return false }

        hotkeyManager?.stop()
        isHotkeyActive = false
        hotkeyStatusMessage = "Hotkey capture in progress"
        return true
    }

    func resumeHotkeyAfterShortcutCapture(shouldRestore: Bool) {
        guard shouldRestore else { return }

        _ = initializeHotkey(promptIfMissing: false)
    }

    func recheckPermissionsAndHotkey(attempts: Int = 3, interval: TimeInterval = 0.35) {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let retryCount = max(1, attempts)

            for attempt in 1...retryCount {
                self.refreshPermissionsAndHotkey(promptIfMissing: false)

                guard !self.permissionStatus.accessibility else {
                    return
                }

                guard attempt < retryCount else {
                    return
                }

                let intervalNanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }
    }
    
    // MARK: - Server Management

    /// Auto-start server on app launch if preferences allow
    private func autoStartServer() async {
        guard !Constants.isRunningTests else { return }

        let hasPreference = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.autoStartServer) != nil
        let autoStart = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoStartServer)

        await checkModelDownloadStatus()
        await ensureDefaultModelDownloadedIfNeeded()

        if hasPreference && autoStart {
            Log.app.info("Auto-starting server on launch...")
            await startServer()
        }
    }

    func startServer() async {
        switch state {
        case .idle, .error:
            break
        default:
            return
        }

        serverStartupStage = .preparingRuntime
        lastDiagnosticErrorDetails = nil
        state = .serverStarting

        do {
            // Start server with selected model pre-loaded
            try await serverManager?.start(model: selectedModel.identifier) { [weak self] stage in
                self?.serverStartupStage = stage
            }
            serverStartupStage = nil
            lastDiagnosticErrorDetails = nil
            state = .serverRunning
            Log.server.info("Server started successfully with model: \(selectedModel.name)")
        } catch {
            serverStartupStage = nil
            if let serverError = error as? ServerError {
                lastDiagnosticErrorDetails = serverError.diagnosticDetails
            } else {
                lastDiagnosticErrorDetails = error.localizedDescription
            }
            state = .error(error.localizedDescription)
            Log.server.error("Server failed to start: \(error)")
        }
    }
    
    func stopServer() {
        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
        clearRecordingModePrompt()
        webSocketClient?.disconnect()
        webSocketClient = nil
        stopAudioCapture()
        serverManager?.stop()
        serverStartupStage = nil
        state = .idle
        Log.server.info("Server stopped")
    }
    
    // MARK: - Recording Control
    
    func startRecording() {
        Log.app.info("startRecording requested (state: \(state), mode: \(recordingMode))")
        guard state == .serverRunning else {
            Log.app.warning("Cannot start recording - server not running")
            return
        }

        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
        clearRecordingModePrompt()
        webSocketClient?.disconnect()
        webSocketClient = nil
        
        state = .connecting
        currentTranscription = ""
        lastCompletedTranscription = nil
        sessionWordCount = 0
        sessionStartTime = Date()
        
        // Connect WebSocket
        webSocketClient = WebSocketClient(serverURL: Constants.Server.websocketURL)
        webSocketClient?.delegate = self
        webSocketClient?.connect()
    }
    
    func stopRecording() {
        Log.app.info("stopRecording requested (state: \(state), mode: \(recordingMode))")
        guard state == .recording || state == .connecting else { return }
        
        // Stop audio first
        stopAudioCapture()

        scheduleWebSocketDisconnectAfterFinalTranscriptGrace()
        
        // Save session statistics
        if let startTime = sessionStartTime {
            let completedAt = Date()
            let duration = completedAt.timeIntervalSince(startTime)
            let snapshot = statisticsManager.recordSession(
                wordCount: sessionWordCount,
                duration: duration,
                text: nil,
                language: "en",
                now: completedAt
            )
            applyStatistics(snapshot)
        }
        
        // Reset
        sessionStartTime = nil
        currentTranscription = ""
        audioAmplitude = 0.0
        
        state = .serverRunning
        Log.app.info("Recording stopped")
    }

    func cancelRecording() {
        Log.app.info("cancelRecording requested (state: \(state), mode: \(recordingMode))")
        guard state == .recording || state == .connecting else { return }

        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
        stopAudioCapture()
        webSocketClient?.disconnect()
        webSocketClient = nil

        sessionStartTime = nil
        sessionWordCount = 0
        currentTranscription = ""
        lastCompletedTranscription = nil
        audioAmplitude = 0.0

        state = .serverRunning
        Log.app.info("Recording cancelled")
    }

    private func stopAudioCapture() {
        audioCapture?.stopRecording()
        activeAudioSessionID = nil
        audioAmplitude = 0.0
    }

    private func scheduleWebSocketDisconnectAfterFinalTranscriptGrace() {
        pendingWebSocketDisconnectTask?.cancel()
        guard let client = webSocketClient else { return }

        pendingWebSocketDisconnectTask = Task { [weak self, weak client] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, let client, self.webSocketClient === client else { return }
            self.webSocketClient?.disconnect()
            self.webSocketClient = nil
            self.pendingWebSocketDisconnectTask = nil
        }
    }
    
    func toggleRecording() {
        Log.app.info("toggleRecording requested (state: \(state), mode: \(recordingMode))")
        if state == .recording || state == .connecting {
            stopRecording()
        } else if state == .serverRunning {
            startRecording()
        }
    }

    func refreshStatistics(currentDate: Date = Date()) {
        applyStatistics(statisticsManager.refreshSnapshot(currentDate: currentDate))
    }

    private func applyStatistics(_ snapshot: StatisticsSnapshot) {
        aggregatedStats = snapshot.total
        todayStats = snapshot.today
    }
    
    // MARK: - Transcription Handling
    
    private func handleTranscription(_ text: String, isPartial: Bool) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            Log.app.warning("Received empty transcription, ignoring")
            return
        }

        logTranscription(trimmedText, isPartial: isPartial)
        
        // Update displayed transcription
        currentTranscription = trimmedText
        
        // For incremental insertion mode: insert each transcription as it arrives
        // The server sends transcription after each speech pause (via VAD)
        if !isPartial {
            lastCompletedTranscription = trimmedText

            // Count words
            let wordCount = trimmedText.split(separator: " ").count
            sessionWordCount += wordCount

            logInsertionAttempt(wordCount: wordCount, textLength: trimmedText.count)
            
            // Insert text at cursor
            if let inserter = textInserter {
                let insertionText = sanitizeForInsertion(trimmedText) + " "
                performInsertion(text: insertionText, inserter: inserter)
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
        refreshPermissionStatus(source: "testInsertion")
        guard let inserter = textInserter else {
            Log.textInsertion.error("TextInserter is nil. Cannot insert text.")
            lastInsertionError = "Text inserter not initialized."
            lastInsertionMethod = nil
            return
        }
        performInsertion(text: sanitizeForInsertion(text), inserter: inserter)
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

    private func sanitizeForInsertion(_ text: String) -> String {
        let isSafeModeEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.safeModeEnabled)
        return Self.sanitizeForInsertion(text, safeModeEnabled: isSafeModeEnabled)
    }

    static func sanitizeForInsertion(_ text: String, safeModeEnabled: Bool) -> String {
        guard safeModeEnabled else { return text }
        return text.components(separatedBy: .newlines).joined(separator: " ")
    }

    private func logTranscription(_ text: String, isPartial: Bool) {
        #if DEBUG
        Log.app.info("Received transcription: \"\(text)\" (partial: \(isPartial))")
        #else
        Log.app.info("Received transcription (\(text.count) chars, partial: \(isPartial))")
        #endif
    }

    private func logInsertionAttempt(wordCount: Int, textLength: Int) {
        #if DEBUG
        Log.textInsertion.info("Attempting to insert text (\(wordCount) words, \(textLength) chars)")
        #else
        Log.textInsertion.info("Attempting to insert text (\(wordCount) words)")
        #endif
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
        guard model.identifier != selectedModel.identifier else {
            return
        }

        selectedModel = model
        UserDefaults.standard.set(model.identifier, forKey: Constants.UserDefaultsKeys.selectedModel)
        lastDiagnosticErrorDetails = nil
        modelDownloadError = nil

        // Check if model is downloaded
        await checkModelDownloadStatus()

        // If server is running, restart with new model
        if state == .serverRunning, modelDownloadStatus == .downloaded {
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

    // MARK: - Audio Input Selection

    func refreshAudioInputDevices() {
        selectedAudioInputDeviceID = audioCapture?.selectedInputDeviceID() ?? AudioInputDevice.systemDefaultID
        audioInputDevices = audioCapture?.refreshAvailableInputDevices() ?? [.systemDefault]
    }

    func setSelectedAudioInputDeviceID(_ deviceID: String) {
        let normalizedID = AudioInputDeviceSelection.normalizedSelectionID(deviceID)
        guard normalizedID != selectedAudioInputDeviceID else { return }

        let wasRecording = state == .recording || state == .connecting
        if wasRecording {
            stopRecording()
        } else {
            clearRecordingModePrompt()
        }

        audioCapture?.setSelectedInputDeviceID(normalizedID)
        selectedAudioInputDeviceID = normalizedID
        refreshAudioInputDevices()

        if wasRecording {
            recordingModePromptMessage = "Recording stopped. Press \(currentHotkey.displayString) to start again with the selected microphone."
            Log.app.info("Microphone changed while active; stopped recording before switching input")
        }
    }

    // MARK: - Preferences

    func setRecordingMode(_ mode: RecordingMode) {
        guard recordingMode != mode else { return }

        let wasRecording = state == .recording || state == .connecting
        if wasRecording {
            stopRecording()
        } else {
            clearRecordingModePrompt()
        }

        recordingMode = mode
        hotkeyManager?.recordingMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Constants.UserDefaultsKeys.recordingMode)

        if wasRecording {
            recordingModePromptMessage = "Recording stopped. Press \(currentHotkey.displayString) to start again in \(mode.displayName) mode."
            Log.app.info("Recording mode changed while active; stopped recording and showing restart prompt for \(mode.displayName) mode")
        }
    }

    func setHotkeyShortcut(_ shortcut: HotkeyShortcut) {
        if case .invalid(let message) = HotkeyShortcutRules.validation(for: shortcut) {
            Log.hotkey.warning("Rejected invalid hotkey shortcut: \(message)")
            return
        }

        guard currentHotkey != shortcut else { return }

        let wasRecording = state == .recording || state == .connecting
        if wasRecording {
            stopRecording()
        } else {
            clearRecordingModePrompt()
        }

        currentHotkey = shortcut
        HotkeyShortcutStore.save(shortcut)
        hotkeyManager?.setHotkey(shortcut)

        if wasRecording {
            recordingModePromptMessage = "Recording stopped. Press \(shortcut.displayString) to start again."
            Log.app.info("Hotkey changed while active; stopped recording and applied \(shortcut.displayString)")
        }
    }

    func clearRecordingModePrompt() {
        recordingModePromptMessage = nil
    }
    
    // MARK: - Shutdown
    
    func shutdown() {
        permissionRefreshTask?.cancel()
        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
        stopRecording()
        stopServer()
        hotkeyManager?.stop()
        isHotkeyActive = false
    }

    /// Best-effort cleanup before app termination to avoid leaving server processes running.
    func shutdownForTermination() async {
        permissionRefreshTask?.cancel()
        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
        stopRecording()
        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
        webSocketClient?.disconnect()
        webSocketClient = nil
        stopAudioCapture()
        await serverManager?.stopAndWait(timeout: 2.0)
        hotkeyManager?.stop()
        isHotkeyActive = false
        state = .idle
    }
}

// MARK: - WebSocketClientDelegate

extension AppStateManager: WebSocketClientDelegate {
    
    nonisolated func webSocketDidConnect(_ client: WebSocketClient) {
        Task { @MainActor in
            guard client === webSocketClient else {
                Log.websocket.debug("Ignoring connect callback from stale WebSocket client")
                return
            }
            Log.websocket.info("webSocketDidConnect received (state: \(state))")
            Log.websocket.info("WebSocket connected, starting audio...")

            // Send configuration with selected model
            let config = ClientConfig.with(model: selectedModel.identifier)
            webSocketClient?.sendConfiguration(config)

            // Start audio capture
            do {
                activeAudioSessionID = try audioCapture?.startRecording()
                state = .recording
            } catch {
                Log.audio.error("Failed to start audio: \(error)")
                state = .error(error.localizedDescription)
                webSocketClient?.disconnect()
                webSocketClient = nil
            }
        }
    }
    
    nonisolated func webSocketDidDisconnect(_ client: WebSocketClient, error: Error?) {
        Task { @MainActor in
            guard client === webSocketClient else {
                Log.websocket.debug("Ignoring disconnect callback from stale WebSocket client")
                return
            }
            Log.websocket.info("webSocketDidDisconnect received (state: \(state), error: \(error?.localizedDescription ?? "none"))")
            stopAudioCapture()
            webSocketClient = nil
            if state == .recording || state == .connecting {
                if let error = error {
                    Log.websocket.error("WebSocket disconnected with error: \(error)")
                    lastDiagnosticErrorDetails = error.localizedDescription
                    state = .error(userFacingWebSocketErrorMessage(error))
                    return
                }
                state = .serverRunning
            }
        }
    }
    
    nonisolated func webSocketDidReceiveTranscription(_ client: WebSocketClient, transcription: ServerTranscription) {
        Task { @MainActor in
            guard client === webSocketClient else {
                Log.websocket.debug("Ignoring transcription from stale WebSocket client")
                return
            }
            handleTranscription(transcription.text, isPartial: transcription.isPartial)
        }
    }
    
    nonisolated func webSocketDidReceiveStatus(_ client: WebSocketClient, status: ServerStatus) {
        Task { @MainActor in
            guard client === webSocketClient else {
                Log.websocket.debug("Ignoring status from stale WebSocket client")
                return
            }
            Log.server.info("Server status: \(status.status) - \(status.message)")
        }
    }
}

// MARK: - AudioCaptureDelegate

extension AppStateManager: AudioCaptureDelegate {
    
    nonisolated func audioCaptureDidReceiveBuffer(_ buffer: Data, sessionID: AudioCaptureSessionID) {
        Task { @MainActor in
            guard state == .recording, activeAudioSessionID == sessionID else {
                Log.audio.debug("Ignoring audio buffer from stale capture session")
                return
            }
            webSocketClient?.sendAudioData(buffer)
        }
    }
    
    nonisolated func audioCaptureDidUpdateAmplitude(_ amplitude: Float, sessionID: AudioCaptureSessionID) {
        Task { @MainActor in
            guard state == .recording, activeAudioSessionID == sessionID else { return }
            audioAmplitude = amplitude
        }
    }
    
    nonisolated func audioCaptureDidFail(error: Error, sessionID: AudioCaptureSessionID) {
        Task { @MainActor in
            guard activeAudioSessionID == sessionID else {
                Log.audio.debug("Ignoring error from stale capture session: \(error.localizedDescription)")
                return
            }
            Log.audio.error("Audio capture failed: \(error)")
            stopAudioCapture()
            webSocketClient?.disconnect()

            if recoverFromAudioRouteChangeIfNeeded(error) {
                return
            }

            state = .error(error.localizedDescription)
        }
    }

    private func recoverFromAudioRouteChangeIfNeeded(_ error: Error) -> Bool {
        guard let audioError = error as? AudioError else { return false }

        let promptMessage: String
        switch audioError {
        case .selectedInputUnavailable:
            promptMessage = "Recording stopped because the selected microphone is unavailable. Choose another microphone or reconnect it, then press \(currentHotkey.displayString) to start again."
        case .inputDeviceChanged:
            promptMessage = "Recording stopped because the active microphone changed. Press \(currentHotkey.displayString) to start again."
        default:
            return false
        }

        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
        sessionStartTime = nil
        sessionWordCount = 0
        currentTranscription = ""
        audioAmplitude = 0.0
        lastCompletedTranscription = nil
        refreshAudioInputDevices()
        recordingModePromptMessage = promptMessage
        lastDiagnosticErrorDetails = nil
        state = .serverRunning
        return true
    }

    private func userFacingWebSocketErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if Constants.Models.isQwenModelIdentifier(selectedModel.identifier),
           (message.contains("ModelConfig.__init__()") ||
            message.contains("Model type None not supported") ||
            message.contains("does not recognize this architecture") ||
            message.contains("qwen3_asr")) {
            return Constants.Models.startupValidationMessage(for: selectedModel, rawError: message)
        }

        return message
    }
}

// MARK: - HotkeyManagerDelegate

extension AppStateManager: HotkeyManagerDelegate {
    
    nonisolated func hotkeyDidTriggerStart() {
        Task { @MainActor in
            Log.hotkey.info("Hotkey start trigger received (mode: \(recordingMode), state: \(state))")
            startRecording()
        }
    }
    
    nonisolated func hotkeyDidTriggerStop() {
        Task { @MainActor in
            Log.hotkey.info("Hotkey stop trigger received (mode: \(recordingMode), state: \(state))")
            stopRecording()
        }
    }

    nonisolated func hotkeyDidCancelRecording() {
        Task { @MainActor in
            Log.hotkey.info("Hotkey cancel trigger received (mode: \(recordingMode), state: \(state))")
            cancelRecording()
        }
    }
}
