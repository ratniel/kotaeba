import XCTest
@testable import KotaebaApp

@MainActor
final class AppStateManagerTests: XCTestCase {
    private var originalRecordingMode: String?
    private var originalHotkeyKeyCode: Any?
    private var originalHotkeyModifiers: Any?

    override func setUp() {
        super.setUp()
        originalRecordingMode = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.recordingMode)
        originalHotkeyKeyCode = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.hotkeyKeyCode)
        originalHotkeyModifiers = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.hotkeyModifiers)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.recordingMode)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.hotkeyKeyCode)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.hotkeyModifiers)
    }

    override func tearDown() {
        if let originalRecordingMode {
            UserDefaults.standard.set(originalRecordingMode, forKey: Constants.UserDefaultsKeys.recordingMode)
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.recordingMode)
        }
        restore(originalHotkeyKeyCode, forKey: Constants.UserDefaultsKeys.hotkeyKeyCode)
        restore(originalHotkeyModifiers, forKey: Constants.UserDefaultsKeys.hotkeyModifiers)
        originalRecordingMode = nil
        originalHotkeyKeyCode = nil
        originalHotkeyModifiers = nil
        super.tearDown()
    }

    func testAutoStartIsSkippedDuringTests() async {
        let mockServer = MockServerManager()

        _ = AppStateManager(serverManager: mockServer, shouldAutoStartServer: true)

        await Task.yield()

        XCTAssertFalse(mockServer.startCalled)
    }

    func testStartServerUpdatesState() async {
        let mockServer = MockServerManager()
        let manager = AppStateManager(serverManager: mockServer, shouldAutoStartServer: false)

        XCTAssertEqual(manager.state, AppState.idle)

        await manager.startServer()

        XCTAssertTrue(mockServer.startCalled)
        XCTAssertEqual(manager.state, AppState.serverRunning)
    }

    func testStopServerUpdatesState() async {
        let mockServer = MockServerManager()
        let manager = AppStateManager(serverManager: mockServer, shouldAutoStartServer: false)

        await manager.startServer()
        manager.stopServer()

        XCTAssertTrue(mockServer.stopCalled)
        XCTAssertEqual(manager.state, AppState.idle)
    }

    func testChangingModeWhileConnectingStopsAndPromptsForNewMode() async {
        let manager = AppStateManager(serverManager: MockServerManager(), shouldAutoStartServer: false)

        await manager.startServer()
        manager.startRecording()

        XCTAssertEqual(manager.state, AppState.connecting)

        manager.setRecordingMode(.toggle)

        XCTAssertEqual(manager.state, AppState.serverRunning)
        XCTAssertEqual(manager.recordingMode, .toggle)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.recordingMode),
            RecordingMode.toggle.rawValue
        )
        XCTAssertEqual(
            manager.recordingModePromptMessage,
            "Recording stopped. Press \(Constants.Hotkey.defaultDisplayString) to start again in \(RecordingMode.toggle.displayName) mode."
        )

        manager.shutdown()
    }

    func testSettingSameRecordingModeDoesNotCreatePrompt() {
        let manager = AppStateManager(serverManager: MockServerManager(), shouldAutoStartServer: false)

        manager.setRecordingMode(.hold)

        XCTAssertEqual(manager.recordingMode, .hold)
        XCTAssertNil(manager.recordingModePromptMessage)
    }

    func testStartingRecordingClearsModePrompt() async {
        let manager = AppStateManager(serverManager: MockServerManager(), shouldAutoStartServer: false)

        await manager.startServer()
        manager.startRecording()
        manager.setRecordingMode(.toggle)

        XCTAssertNotNil(manager.recordingModePromptMessage)

        manager.startRecording()

        XCTAssertNil(manager.recordingModePromptMessage)

        manager.shutdown()
    }

    func testSetHotkeyShortcutSavesPreference() {
        let manager = AppStateManager(serverManager: MockServerManager(), shouldAutoStartServer: false)
        let shortcut = HotkeyShortcut(keyCode: 49, modifiers: [.control, .option])

        manager.setHotkeyShortcut(shortcut)

        XCTAssertEqual(manager.currentHotkey, shortcut)
        XCTAssertEqual(HotkeyShortcutStore.load(), shortcut)
    }

    func testChangingHotkeyWhileConnectingStopsAndPromptsForNewShortcut() async {
        let manager = AppStateManager(serverManager: MockServerManager(), shouldAutoStartServer: false)
        let shortcut = HotkeyShortcut(keyCode: 49, modifiers: [.control, .option])

        await manager.startServer()
        manager.startRecording()

        XCTAssertEqual(manager.state, AppState.connecting)

        manager.setHotkeyShortcut(shortcut)

        XCTAssertEqual(manager.state, AppState.serverRunning)
        XCTAssertEqual(manager.currentHotkey, shortcut)
        XCTAssertEqual(manager.recordingModePromptMessage, "Recording stopped. Press ⌃⌥Space to start again.")

        manager.shutdown()
    }

    func testShutdownForTerminationFinalizesPendingSessionBeforeDisconnect() async {
        let mockServer = MockServerManager()
        let mockAudioCapture = MockAudioCapture()
        let mockStatistics = MockStatisticsManager()
        let mockWebSocket = MockWebSocketClient()
        let manager = AppStateManager(
            serverManager: mockServer,
            audioCapture: mockAudioCapture,
            statisticsManager: mockStatistics,
            webSocketClientFactory: { _ in mockWebSocket },
            shouldAutoStartServer: false
        )

        await manager.startServer()
        manager.startRecording()
        manager.webSocketDidConnect(mockWebSocket)
        await Task.yield()

        manager.webSocketDidReceiveTranscription(
            mockWebSocket,
            transcription: ServerTranscription(
                text: "hello world",
                segments: nil,
                isPartial: false,
                language: "en",
                confidence: nil
            )
        )
        await Task.yield()

        await manager.shutdownForTermination()

        XCTAssertEqual(mockStatistics.recordedSessions.count, 1)
        XCTAssertEqual(mockStatistics.recordedSessions[0].wordCount, 2)
        XCTAssertEqual(mockStatistics.recordedSessions[0].text, "hello world")
        XCTAssertTrue(mockWebSocket.disconnectCalled)
        XCTAssertTrue(mockServer.stopCalled)
        XCTAssertEqual(manager.state, AppState.idle)
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

private final class MockServerManager: ServerManaging {
    var unexpectedExitHandler: (@MainActor (String) -> Void)?
    private(set) var startCalled = false
    private(set) var stopCalled = false

    func start(model: String, progressHandler: ServerStartupProgressHandler?) async throws {
        startCalled = true
        progressHandler?(.launchingServer)
    }

    func stop() {
        stopCalled = true
    }

    func stopAndWait(timeout: TimeInterval) async {
        stop()
    }

    func checkModelExists(_ modelIdentifier: String) async throws -> Bool {
        return true
    }

    func validateModelCompatibility(_ modelIdentifier: String) async throws {}

    func downloadModel(_ modelIdentifier: String, progressHandler: ((Double) -> Void)?) async throws {
        progressHandler?(1.0)
    }
}

@MainActor
private final class MockStatisticsManager: StatisticsManaging {
    struct RecordedSession {
        let wordCount: Int
        let duration: TimeInterval
        let text: String?
        let language: String
        let modelIdentifier: String?
        let insertionMethod: String?
        let insertionError: String?
        let sourceAppName: String?
        let now: Date
    }

    var isAvailable = true
    var lastError: Error?
    private(set) var recordedSessions: [RecordedSession] = []

    func getSnapshot(currentDate: Date) -> StatisticsSnapshot {
        snapshot
    }

    func refreshSnapshot(currentDate: Date) -> StatisticsSnapshot {
        snapshot
    }

    func recordSession(
        wordCount: Int,
        duration: TimeInterval,
        text: String?,
        language: String,
        modelIdentifier: String?,
        insertionMethod: String?,
        insertionError: String?,
        sourceAppName: String?,
        now: Date
    ) -> StatisticsSnapshot {
        recordedSessions.append(
            RecordedSession(
                wordCount: wordCount,
                duration: duration,
                text: text,
                language: language,
                modelIdentifier: modelIdentifier,
                insertionMethod: insertionMethod,
                insertionError: insertionError,
                sourceAppName: sourceAppName,
                now: now
            )
        )
        return snapshot
    }

    func getAggregatedStats() -> AggregatedStats {
        snapshot.total
    }

    func getTodayStats(currentDate: Date) -> AggregatedStats {
        snapshot.today
    }

    func getRecentSessions(limit: Int) -> [TranscriptionSession] {
        recordedSessions.suffix(limit).map { session in
            TranscriptionSession(
                startTime: session.now.addingTimeInterval(-session.duration),
                endTime: session.now,
                wordCount: session.wordCount,
                duration: session.duration,
                transcribedText: session.text,
                language: session.language,
                modelIdentifier: session.modelIdentifier,
                insertionMethod: session.insertionMethod,
                insertionError: session.insertionError,
                sourceAppName: session.sourceAppName
            )
        }
    }

    func clearAllData(currentDate: Date) -> StatisticsSnapshot {
        recordedSessions = []
        return snapshot
    }

    private var snapshot: StatisticsSnapshot {
        let wordCount = recordedSessions.reduce(0) { $0 + $1.wordCount }
        let duration = recordedSessions.reduce(0.0) { $0 + $1.duration }
        let aggregate = AggregatedStats(
            totalWords: wordCount,
            totalDuration: duration,
            sessionCount: recordedSessions.count
        )
        return StatisticsSnapshot(total: aggregate, today: aggregate)
    }
}

private final class MockWebSocketClient: WebSocketClienting {
    weak var delegate: WebSocketClientDelegate?
    private(set) var connectCalled = false
    private(set) var disconnectCalled = false

    func connect() {
        connectCalled = true
    }

    func disconnect() {
        disconnectCalled = true
    }

    func sendConfiguration(_ config: ClientConfig) {}

    func sendAudioData(_ data: Data) {}

    func sendText(_ text: String) {}
}

private final class MockAudioCapture: AudioCapturing {
    weak var delegate: AudioCaptureDelegate?
    var inputDevicesDidChange: (() -> Void)?
    private(set) var stopRecordingCallCount = 0

    func requestPermission() async -> Bool {
        true
    }

    func checkPermission() -> Bool {
        true
    }

    func startRecording() throws -> AudioCaptureSessionID {
        AudioCaptureSessionID()
    }

    func stopRecording() {
        stopRecordingCallCount += 1
    }

    func refreshAvailableInputDevices() -> [AudioInputDevice] {
        [.systemDefault]
    }

    func selectedInputDeviceID() -> String {
        AudioInputDevice.systemDefaultID
    }

    func setSelectedInputDeviceID(_ deviceID: String) {}
}
