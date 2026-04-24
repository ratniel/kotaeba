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

    func downloadModel(_ modelIdentifier: String, progressHandler: ((Double) -> Void)?) async throws {
        progressHandler?(1.0)
    }
}
