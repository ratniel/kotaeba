import XCTest
@testable import KotaebaApp

@MainActor
final class AppStateManagerTests: XCTestCase {
    func testStartServerUpdatesState() async {
        let mockServer = MockServerManager()
        let manager = AppStateManager(serverManager: mockServer, autoStartServer: false)

        XCTAssertEqual(manager.state, .idle)

        await manager.startServer()

        XCTAssertTrue(mockServer.startCalled)
        XCTAssertEqual(manager.state, .serverRunning)
    }

    func testStopServerUpdatesState() async {
        let mockServer = MockServerManager()
        let manager = AppStateManager(serverManager: mockServer, autoStartServer: false)

        await manager.startServer()
        manager.stopServer()

        XCTAssertTrue(mockServer.stopCalled)
        XCTAssertEqual(manager.state, .idle)
    }
}

private final class MockServerManager: ServerManaging {
    private(set) var startCalled = false
    private(set) var stopCalled = false

    func start(model: String) async throws {
        startCalled = true
    }

    func stop() {
        stopCalled = true
    }

    func checkModelExists(_ modelIdentifier: String) async throws -> Bool {
        return true
    }

    func downloadModel(_ modelIdentifier: String, progressHandler: ((Double) -> Void)?) async throws {
        progressHandler?(1.0)
    }
}
