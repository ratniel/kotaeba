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
    private static let finalTranscriptGracePeriodNanoseconds: UInt64 = 1_200_000_000
    
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
    @Published private(set) var customModels: [Constants.Models.Model] = []
    @Published private(set) var customModelValidationStatus: CustomModelValidationStatus = .idle
    @Published private(set) var customModelValidationError: String?
    @Published private(set) var lastDiagnosticErrorDetails: String?
    @Published private(set) var serverStartupStage: ServerStartupStage?
    @Published private(set) var aggregatedStats: AggregatedStats = .empty
    @Published private(set) var todayStats: AggregatedStats = .empty
    var availableModels: [Constants.Models.Model] {
        Constants.Models.mergedModels(
            bundledModels: Constants.Models.catalog.models,
            customModels: customModels
        )
    }
    var modelPreflightState: ModelPreflightState {
        if customModelValidationStatus.isRunning {
            return .validatingCustomModel
        }
        return ModelPreflightState.resolve(appState: state, downloadStatus: modelDownloadStatus)
    }
    var isModelSelectionLocked: Bool {
        modelPreflightState.locksModelSelection || state == .connecting || state == .recording
    }
    var modelSelectionLockMessage: String? {
        modelPreflightState.selectionLockMessage ?? (
            state == .connecting || state == .recording
                ? "Stop the active recording before changing models."
                : nil
        )
    }
    @Published private(set) var recentTranscriptionSessions: [TranscriptionSession] = []
    @Published private(set) var audioInputDevices: [AudioInputDevice] = [.systemDefault]
    @Published private(set) var selectedAudioInputDeviceID = AudioInputDevice.systemDefaultID
    
    // MARK: - Components
    
    private var serverManager: ServerManaging?
    private var audioCapture: (any AudioCapturing)?
    private var webSocketClient: (any WebSocketClienting)?
    private var hotkeyManager: HotkeyManager?
    private var textInserter: TextInserter?
    private let statisticsManager: any StatisticsManaging
    private let webSocketClientFactory: @MainActor (URL) -> any WebSocketClienting
    private let sourceAppNameProvider: @MainActor () -> String?
    private let huggingFaceModelInfoProvider: (String, String?) async throws -> HuggingFaceModelInfo
    private let huggingFaceTokenProvider: @MainActor () -> String?
    private var permissionRefreshTask: Task<Void, Never>?
    private var pendingWebSocketDisconnectTask: Task<Void, Never>?
    private var activeAudioSessionID: AudioCaptureSessionID?
    
    // MARK: - Session Tracking
    
    private var sessionStartTime: Date?
    private var sessionWordCount: Int = 0
    private var sessionTranscriptChunks: [String] = []
    private var sessionLanguage: String = "en"
    private var sessionModelIdentifier: String?
    private var sessionInsertionMethod: String?
    private var sessionInsertionError: String?
    private var sessionSourceAppName: String?
    private var pendingSessionCompletedAt: Date?
    
    // MARK: - Initialization

    private init() {
        self.statisticsManager = StatisticsManager.shared
        self.webSocketClientFactory = { WebSocketClient(serverURL: $0) }
        self.sourceAppNameProvider = { NSWorkspace.shared.frontmostApplication?.localizedName }
        self.huggingFaceModelInfoProvider = HuggingFaceModelLookup.fetchModelInfo
        self.huggingFaceTokenProvider = {
            KeychainSecretStore.string(for: Constants.SecureSettingsKeys.huggingFaceToken)
        }
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
        webSocketClientFactory: @MainActor @escaping (URL) -> any WebSocketClienting = { WebSocketClient(serverURL: $0) },
        sourceAppNameProvider: @MainActor @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.localizedName
        },
        huggingFaceModelInfoProvider: @escaping (String, String?) async throws -> HuggingFaceModelInfo = HuggingFaceModelLookup.fetchModelInfo,
        huggingFaceTokenProvider: @MainActor @escaping () -> String? = {
            KeychainSecretStore.string(for: Constants.SecureSettingsKeys.huggingFaceToken)
        },
        shouldAutoStartServer: Bool = false
    ) {
        self.statisticsManager = statisticsManager ?? StatisticsManager.shared
        self.webSocketClientFactory = webSocketClientFactory
        self.sourceAppNameProvider = sourceAppNameProvider
        self.huggingFaceModelInfoProvider = huggingFaceModelInfoProvider
        self.huggingFaceTokenProvider = huggingFaceTokenProvider
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
        customModels = CustomModelCatalogStore.loadModels()

        if let modeString = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.recordingMode),
           let mode = RecordingMode(rawValue: modeString) {
            recordingMode = mode
        }

        // Load selected model
        if let modelId = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.selectedModel) {
            if let model = model(withIdentifier: modelId) {
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
        cancelPendingWebSocketDisconnect()
        stopAudioCapture()
        disconnectCurrentWebSocket()
        resetRecordingSession(clearCompletedTranscription: true)
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
        cancelPendingWebSocketDisconnect()
        clearRecordingModePrompt()
        stopAudioCapture()
        finalizePendingRecordingSessionIfNeeded()
        disconnectCurrentWebSocket()
        resetRecordingSession(clearCompletedTranscription: true)
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

        cancelPendingWebSocketDisconnect()
        clearRecordingModePrompt()
        finalizePendingRecordingSessionIfNeeded()
        stopAudioCapture()
        disconnectCurrentWebSocket()
        
        state = .connecting
        currentTranscription = ""
        lastCompletedTranscription = nil
        sessionWordCount = 0
        sessionStartTime = Date()
        sessionTranscriptChunks = []
        sessionLanguage = "en"
        sessionModelIdentifier = selectedModel.identifier
        sessionInsertionMethod = nil
        sessionInsertionError = nil
        sessionSourceAppName = nil
        pendingSessionCompletedAt = nil
        
        // Connect WebSocket
        let client = webSocketClientFactory(Constants.Server.websocketURL)
        webSocketClient = client
        client.delegate = self
        client.connect()
    }
    
    func stopRecording() {
        Log.app.info("stopRecording requested (state: \(state), mode: \(recordingMode))")
        guard state == .recording || state == .connecting else { return }
        
        // Stop audio first so no new buffers are sent during final-transcript grace.
        stopAudioCapture()

        pendingSessionCompletedAt = Date()
        if webSocketClient != nil {
            scheduleWebSocketDisconnectAfterFinalTranscriptGrace()
        } else {
            finalizePendingRecordingSessionIfNeeded()
        }

        currentTranscription = ""
        audioAmplitude = 0.0
        
        state = .serverRunning
        Log.app.info("Recording stopped")
    }

    func cancelRecording() {
        Log.app.info("cancelRecording requested (state: \(state), mode: \(recordingMode))")
        guard state == .recording || state == .connecting else { return }

        cancelPendingWebSocketDisconnect()
        stopAudioCapture()
        disconnectCurrentWebSocket()

        resetRecordingSession(clearCompletedTranscription: true)

        state = .serverRunning
        Log.app.info("Recording cancelled")
    }

    private func cancelPendingWebSocketDisconnect() {
        pendingWebSocketDisconnectTask?.cancel()
        pendingWebSocketDisconnectTask = nil
    }

    private func stopAudioCapture() {
        audioCapture?.stopRecording()
        activeAudioSessionID = nil
        audioAmplitude = 0.0
    }

    private func disconnectCurrentWebSocket() {
        webSocketClient?.disconnect()
        webSocketClient = nil
    }

    private func resetRecordingSession(clearCompletedTranscription: Bool) {
        sessionStartTime = nil
        sessionWordCount = 0
        sessionTranscriptChunks = []
        sessionLanguage = "en"
        sessionModelIdentifier = nil
        sessionInsertionMethod = nil
        sessionInsertionError = nil
        sessionSourceAppName = nil
        pendingSessionCompletedAt = nil
        currentTranscription = ""
        audioAmplitude = 0.0
        activeAudioSessionID = nil
        if clearCompletedTranscription {
            lastCompletedTranscription = nil
        }
    }

    private func isCurrentWebSocketClient(_ client: any WebSocketClienting) -> Bool {
        guard let webSocketClient else { return false }
        return client === webSocketClient
    }

    private func scheduleWebSocketDisconnectAfterFinalTranscriptGrace() {
        cancelPendingWebSocketDisconnect()
        guard let client = webSocketClient else { return }

        pendingWebSocketDisconnectTask = Task { @MainActor [weak self, weak client] in
            do {
                try await Task.sleep(nanoseconds: Self.finalTranscriptGracePeriodNanoseconds)
            } catch {
                return
            }
            guard let self, let client, self.isCurrentWebSocketClient(client) else { return }
            self.finalizePendingRecordingSessionIfNeeded()
            self.disconnectCurrentWebSocket()
            self.pendingWebSocketDisconnectTask = nil
        }
    }

    private func finalizePendingRecordingSessionIfNeeded() {
        guard let startTime = sessionStartTime, let completedAt = pendingSessionCompletedAt else { return }

        let duration = max(0, completedAt.timeIntervalSince(startTime))
        let transcript = combinedSessionTranscript()
        let snapshot = statisticsManager.recordSession(
            wordCount: sessionWordCount,
            duration: duration,
            text: transcript,
            language: sessionLanguage,
            modelIdentifier: sessionModelIdentifier,
            insertionMethod: sessionInsertionMethod,
            insertionError: sessionInsertionError,
            sourceAppName: sessionSourceAppName,
            now: completedAt
        )
        applyStatistics(snapshot)
        resetRecordingSession(clearCompletedTranscription: false)
    }

    private func combinedSessionTranscript() -> String? {
        let text = sessionTranscriptChunks
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func currentSourceAppName() -> String? {
        sourceAppNameProvider()
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

    func clearTranscriptionHistory(currentDate: Date = Date()) {
        applyStatistics(statisticsManager.clearAllData(currentDate: currentDate))
    }

    private func applyStatistics(_ snapshot: StatisticsSnapshot) {
        aggregatedStats = snapshot.total
        todayStats = snapshot.today
        recentTranscriptionSessions = statisticsManager.getRecentSessions(limit: 20)
    }
    
    // MARK: - Transcription Handling
    
    private func handleTranscription(_ transcription: ServerTranscription) {
        let text = transcription.text
        let isPartial = transcription.isPartial
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
            sessionTranscriptChunks.append(trimmedText)
            if let language = transcription.language, !language.isEmpty {
                sessionLanguage = language
            }

            // Count words
            let wordCount = trimmedText.split(whereSeparator: { $0.isWhitespace }).count
            sessionWordCount += wordCount

            logInsertionAttempt(wordCount: wordCount, textLength: trimmedText.count)

            captureSessionSourceAppAtInsertionTime()

            // Insert text at cursor
            if let inserter = textInserter {
                let insertionText = sanitizeForInsertion(trimmedText) + " "
                let result = performInsertion(text: insertionText, inserter: inserter)
                recordSessionInsertionResult(result)
            } else {
                Log.textInsertion.error("TextInserter is nil. Cannot insert text.")
                lastInsertionError = "Text inserter not initialized."
                lastInsertionMethod = nil
                sessionInsertionMethod = nil
                sessionInsertionError = lastInsertionError
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
        _ = performInsertion(text: sanitizeForInsertion(text), inserter: inserter)
    }

    private func performInsertion(text: String, inserter: TextInserter) -> TextInsertionResult {
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
        return result
    }

    private func recordSessionInsertionResult(_ result: TextInsertionResult) {
        switch result {
        case .success(let method):
            if sessionInsertionError == nil {
                sessionInsertionMethod = method.rawValue
            }
        case .failure(let error):
            sessionInsertionMethod = nil
            if sessionInsertionError == nil {
                sessionInsertionError = error.localizedDescription
            }
        }
    }

    private func captureSessionSourceAppAtInsertionTime() {
        guard let sourceAppName = currentSourceAppName()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceAppName.isEmpty else {
            return
        }
        sessionSourceAppName = sourceAppName
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

    private func model(withIdentifier identifier: String) -> Constants.Models.Model? {
        let normalizedIdentifier = Constants.Models.normalizedIdentifier(identifier)
        return availableModels.first { $0.identifier == normalizedIdentifier }
    }

    func checkModelDownloadStatus() async {
        if modelDownloadStatus == .downloading {
            return
        }

        let modelIdentifier = selectedModel.identifier
        modelDownloadStatus = .checking

        do {
            let isDownloaded = try await serverManager?.checkModelExists(modelIdentifier) ?? false
            guard selectedModel.identifier == modelIdentifier else {
                Log.server.debug("Ignoring model status result for stale model \(modelIdentifier)")
                return
            }
            modelDownloadStatus = isDownloaded ? .downloaded : .notDownloaded
            modelDownloadError = nil
            modelDownloadProgress = nil
        } catch {
            guard selectedModel.identifier == modelIdentifier else {
                Log.server.debug("Ignoring model status error for stale model \(modelIdentifier): \(error.localizedDescription)")
                return
            }
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
        guard !modelPreflightState.locksModelSelection else {
            Log.server.info(
                "Ignoring model change to \(model.identifier) while model preflight is locked: \(modelPreflightState)"
            )
            return
        }

        let wasActive = state == .recording || state == .connecting
        if wasActive {
            cancelRecording()
            Log.app.info("Model changed while active; stopped recording before switching to \(model.name)")
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

        if wasActive {
            recordingModePromptMessage = "Recording stopped. Press \(currentHotkey.displayString) to start again with \(model.name)."
            Log.app.info("Model changed while active; stopped recording and showing restart prompt for \(model.name)")
        }
    }

    @discardableResult
    func addCustomModel(identifier rawIdentifier: String) async -> Bool {
        let identifier = Constants.Models.normalizedIdentifier(
            rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard !isModelSelectionLocked else {
            customModelValidationError = modelSelectionLockMessage ?? "Wait for current model work to finish."
            return false
        }

        guard Constants.Models.isValidIdentifier(identifier) else {
            customModelValidationError = HuggingFaceModelLookupError.invalidIdentifier(rawIdentifier).localizedDescription
            return false
        }

        if let existingModel = model(withIdentifier: identifier) {
            customModelValidationError = nil
            await setSelectedModel(existingModel)
            return selectedModel.identifier == existingModel.identifier
        }

        guard let serverManager else {
            customModelValidationError = "Server manager unavailable."
            return false
        }

        customModelValidationError = nil
        customModelValidationStatus = .checkingRepository
        defer {
            customModelValidationStatus = .idle
        }

        do {
            let info = try await huggingFaceModelInfoProvider(identifier, huggingFaceTokenProvider())
            try HuggingFaceModelLookup.validateSpeechToTextCandidate(info)

            customModelValidationStatus = .validatingCompatibility
            try await serverManager.validateModelCompatibility(identifier)

            customModelValidationStatus = .saving
            let model = CustomModelCatalogStore.model(for: info)
            CustomModelCatalogStore.upsert(model)
            customModels = CustomModelCatalogStore.loadModels()
            selectedModel = model
            UserDefaults.standard.set(model.identifier, forKey: Constants.UserDefaultsKeys.selectedModel)
            modelDownloadStatus = .downloaded
            modelDownloadError = nil
            modelDownloadProgress = nil
            lastDiagnosticErrorDetails = nil

            if state == .serverRunning {
                Log.server.info("Restarting server with custom model: \(model.name)")
                stopServer()
                await startServer()
            }

            return true
        } catch {
            Log.server.error("Failed to add custom model \(identifier): \(error.localizedDescription)")
            customModelValidationError = error.localizedDescription
            return false
        }
    }

    func clearCustomModelValidationMessage() {
        guard !customModelValidationStatus.isRunning else { return }
        customModelValidationError = nil
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

        let modelIdentifier = selectedModel.identifier
        modelDownloadStatus = .downloading
        modelDownloadError = nil
        modelDownloadProgress = nil

        do {
            try await serverManager.downloadModel(modelIdentifier) { progress in
                Task { @MainActor in
                    guard self.selectedModel.identifier == modelIdentifier else {
                        Log.server.debug("Ignoring download progress for stale model \(modelIdentifier)")
                        return
                    }
                    self.modelDownloadProgress = progress
                }
            }
            guard selectedModel.identifier == modelIdentifier else {
                Log.server.debug("Ignoring completed download for stale model \(modelIdentifier)")
                return
            }
            modelDownloadStatus = .downloaded
            modelDownloadError = nil
            modelDownloadProgress = nil

            if modelIdentifier == Constants.Models.defaultModel.identifier {
                UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.didAutoDownloadDefaultModel)
            }
        } catch {
            guard selectedModel.identifier == modelIdentifier else {
                Log.server.debug("Ignoring download error for stale model \(modelIdentifier): \(error.localizedDescription)")
                return
            }
            Log.server.error("Failed to download model \(modelIdentifier): \(error)")
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
        cancelPendingWebSocketDisconnect()
        stopRecording()
        stopServer()
        hotkeyManager?.stop()
        isHotkeyActive = false
    }

    /// Best-effort cleanup before app termination to avoid leaving server processes running.
    func shutdownForTermination() async {
        permissionRefreshTask?.cancel()
        cancelPendingWebSocketDisconnect()
        stopRecording()
        cancelPendingWebSocketDisconnect()
        finalizePendingRecordingSessionIfNeeded()
        disconnectCurrentWebSocket()
        stopAudioCapture()
        await serverManager?.stopAndWait(timeout: 2.0)
        hotkeyManager?.stop()
        isHotkeyActive = false
        state = .idle
    }
}

// MARK: - WebSocketClientDelegate

private enum AppLifecycleError: LocalizedError {
    case audioCaptureUnavailable

    var errorDescription: String? {
        switch self {
        case .audioCaptureUnavailable:
            return "Audio capture is unavailable."
        }
    }
}

extension AppStateManager: WebSocketClientDelegate {
    
    nonisolated func webSocketDidConnect(_ client: any WebSocketClienting) {
        Task { @MainActor in
            guard isCurrentWebSocketClient(client) else {
                Log.websocket.debug("Ignoring connect callback from stale WebSocket client")
                return
            }
            Log.websocket.info("webSocketDidConnect received (state: \(state))")
            Log.websocket.info("WebSocket connected, starting audio...")

            // Send configuration with selected model
            let config = ClientConfig.with(model: selectedModel.identifier)
            client.sendConfiguration(config)

            // Start audio capture
            do {
                guard let audioCapture else {
                    throw AppLifecycleError.audioCaptureUnavailable
                }
                activeAudioSessionID = try audioCapture.startRecording()
                state = .recording
            } catch {
                Log.audio.error("Failed to start audio: \(error)")
                activeAudioSessionID = nil
                state = .error(error.localizedDescription)
                if isCurrentWebSocketClient(client) {
                    disconnectCurrentWebSocket()
                }
            }
        }
    }
    
    nonisolated func webSocketDidDisconnect(_ client: any WebSocketClienting, error: Error?) {
        Task { @MainActor in
            guard isCurrentWebSocketClient(client) else {
                Log.websocket.debug("Ignoring disconnect callback from stale WebSocket client")
                return
            }
            Log.websocket.info("webSocketDidDisconnect received (state: \(state), error: \(error?.localizedDescription ?? "none"))")
            let hadPendingStoppedSession = pendingSessionCompletedAt != nil
            cancelPendingWebSocketDisconnect()
            stopAudioCapture()
            webSocketClient = nil
            if hadPendingStoppedSession {
                finalizePendingRecordingSessionIfNeeded()
            }
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
    
    nonisolated func webSocketDidReceiveTranscription(_ client: any WebSocketClienting, transcription: ServerTranscription) {
        Task { @MainActor in
            guard isCurrentWebSocketClient(client) else {
                Log.websocket.debug("Ignoring transcription from stale WebSocket client")
                return
            }
            handleTranscription(transcription)
        }
    }
    
    nonisolated func webSocketDidReceiveStatus(_ client: any WebSocketClienting, status: ServerStatus) {
        Task { @MainActor in
            guard isCurrentWebSocketClient(client) else {
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
            disconnectCurrentWebSocket()

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

        cancelPendingWebSocketDisconnect()
        resetRecordingSession(clearCompletedTranscription: true)
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
