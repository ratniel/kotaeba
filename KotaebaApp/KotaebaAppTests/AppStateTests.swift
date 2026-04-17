import XCTest
@testable import KotaebaApp

final class AppStateTests: XCTestCase {
    func testRecordingFlags() {
        XCTAssertTrue(AppState.recording.isRecording)
        XCTAssertFalse(AppState.serverRunning.isRecording)
    }

    func testCanRecord() {
        XCTAssertTrue(AppState.serverRunning.canRecord)
        XCTAssertTrue(AppState.idle.canRecord)
        XCTAssertFalse(AppState.connecting.canRecord)
        XCTAssertFalse(AppState.processing.canRecord)
    }

    func testStatusTextIncludesErrorMessage() {
        let message = "Boom"
        let text = AppState.error(message).statusText
        XCTAssertTrue(text.contains(message))
    }
}
