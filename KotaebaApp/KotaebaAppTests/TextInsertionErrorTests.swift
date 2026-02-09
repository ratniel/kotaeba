import XCTest
@testable import KotaebaApp

final class TextInsertionErrorTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertEqual(TextInsertionError.emptyText.errorDescription, "Empty text cannot be inserted.")
        XCTAssertEqual(TextInsertionError.accessibilityPermissionDenied.errorDescription, "Accessibility permission is not granted.")
        XCTAssertEqual(TextInsertionError.noFocusedElement.errorDescription, "No focused text field found.")
        XCTAssertEqual(TextInsertionError.accessibilityInsertFailed.errorDescription, "Accessibility insertion failed.")
        XCTAssertEqual(TextInsertionError.secureInputEnabled.errorDescription, "Secure input is enabled. Text insertion is blocked by the system.")
        XCTAssertEqual(TextInsertionError.unicodeEventFailed.errorDescription, "Unicode event insertion failed.")
        XCTAssertEqual(TextInsertionError.clipboardFallbackDisabled.errorDescription, "Clipboard fallback is disabled in settings.")
        XCTAssertEqual(TextInsertionError.clipboardSetFailed.errorDescription, "Failed to write text to the clipboard.")
    }
}
