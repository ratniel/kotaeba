import XCTest
@testable import KotaebaApp

@MainActor
final class ModelDownloadStatusTests: XCTestCase {
    func testDisplayText() {
        XCTAssertEqual(ModelDownloadStatus.unknown.displayText, "Unknown")
        XCTAssertEqual(ModelDownloadStatus.checking.displayText, "Checking...")
        XCTAssertEqual(ModelDownloadStatus.downloading.displayText, "Downloading...")
        XCTAssertEqual(ModelDownloadStatus.downloaded.displayText, "Downloaded")
        XCTAssertEqual(ModelDownloadStatus.notDownloaded.displayText, "Not Downloaded")
    }

    func testIcons() {
        XCTAssertEqual(ModelDownloadStatus.unknown.icon, "questionmark.circle")
        XCTAssertEqual(ModelDownloadStatus.checking.icon, "arrow.clockwise")
        XCTAssertEqual(ModelDownloadStatus.downloading.icon, "arrow.down.circle.fill")
        XCTAssertEqual(ModelDownloadStatus.downloaded.icon, "checkmark.circle.fill")
        XCTAssertEqual(ModelDownloadStatus.notDownloaded.icon, "arrow.down.circle")
    }

    func testModelPreflightStateLocksDuringPendingModelWork() {
        XCTAssertEqual(
            ModelPreflightState.resolve(appState: .serverStarting, downloadStatus: .downloaded),
            .validatingAndStartingServer
        )
        XCTAssertEqual(
            ModelPreflightState.resolve(appState: .serverRunning, downloadStatus: .checking),
            .checkingCache
        )
        XCTAssertEqual(
            ModelPreflightState.resolve(appState: .serverRunning, downloadStatus: .downloading),
            .downloading
        )
        XCTAssertEqual(
            ModelPreflightState.resolve(appState: .serverRunning, downloadStatus: .downloaded),
            .idle
        )
        XCTAssertTrue(ModelPreflightState.downloading.locksModelSelection)
        XCTAssertTrue(ModelPreflightState.validatingCustomModel.locksModelSelection)
        XCTAssertTrue(ModelPreflightState.validatingAndStartingServer.locksModelSelection)
        XCTAssertFalse(ModelPreflightState.idle.locksModelSelection)
    }
}
