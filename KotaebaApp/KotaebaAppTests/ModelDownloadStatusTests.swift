import XCTest
@testable import KotaebaApp

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
}
