import XCTest
@testable import KotaebaApp

final class RecordingModeTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(RecordingMode.hold.displayName, "Hold to Record")
        XCTAssertEqual(RecordingMode.toggle.displayName, "Toggle Recording")
    }

    func testDescriptions() {
        XCTAssertTrue(RecordingMode.hold.description.contains("Hold"))
        XCTAssertTrue(RecordingMode.toggle.description.contains("Press"))
    }
}
