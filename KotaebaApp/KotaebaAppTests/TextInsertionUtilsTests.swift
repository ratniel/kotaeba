import XCTest
import AppKit
@testable import KotaebaApp

@MainActor
final class TextInsertionUtilsTests: XCTestCase {
    func testInsertAtBeginning() {
        let result = TextInserter.applyInsertion(text: "Hi ", to: "there", range: CFRange(location: 0, length: 0))
        XCTAssertEqual(result, "Hi there")
    }

    func testReplaceMiddleRange() {
        let result = TextInserter.applyInsertion(text: "swift", to: "hello world", range: CFRange(location: 6, length: 5))
        XCTAssertEqual(result, "hello swift")
    }

    func testInsertAtEnd() {
        let value = "hello"
        let result = TextInserter.applyInsertion(text: "!", to: value, range: CFRange(location: value.utf16.count, length: 0))
        XCTAssertEqual(result, "hello!")
    }

    func testOutOfBoundsRangeAppends() {
        let result = TextInserter.applyInsertion(text: "!", to: "hello", range: CFRange(location: 999, length: 3))
        XCTAssertEqual(result, "hello!")
    }

    func testUnicodeRangeReplace() {
        let value = "Hi 😀 there"
        let result = TextInserter.applyInsertion(text: "🙂", to: value, range: CFRange(location: 3, length: 2))
        XCTAssertEqual(result, "Hi 🙂 there")
    }

    func testNegativeRangeInsertsAtBeginning() {
        let result = TextInserter.applyInsertion(text: "Hi ", to: "there", range: CFRange(location: -4, length: 0))
        XCTAssertEqual(result, "Hi there")
    }

    func testInvalidUTF16BoundaryAppends() {
        let value = "Hi 😀 there"
        let result = TextInserter.applyInsertion(text: "!", to: value, range: CFRange(location: 4, length: 0))
        XCTAssertEqual(result, "Hi 😀 there!")
    }

    func testPasteboardItemClonePreservesMultipleTypes() {
        let customType = NSPasteboard.PasteboardType("com.kotaeba.test.binary")
        let item = NSPasteboardItem()
        item.setString("hello", forType: .string)
        item.setData(Data([0, 1, 2, 3]), forType: customType)

        let clonedItems = TextInserter.clonePasteboardItems([item])

        XCTAssertEqual(clonedItems.count, 1)
        XCTAssertEqual(clonedItems[0].string(forType: .string), "hello")
        XCTAssertEqual(clonedItems[0].data(forType: customType), Data([0, 1, 2, 3]))
    }

    func testPasteboardItemClonePreservesMultipleItems() {
        let first = NSPasteboardItem()
        first.setString("first", forType: .string)
        let second = NSPasteboardItem()
        second.setString("second", forType: .string)

        let clonedItems = TextInserter.clonePasteboardItems([first, second])

        XCTAssertEqual(clonedItems.count, 2)
        XCTAssertEqual(clonedItems[0].string(forType: .string), "first")
        XCTAssertEqual(clonedItems[1].string(forType: .string), "second")
    }

    func testPasteboardCommitRequiresExpectedTextAndChangeCount() {
        XCTAssertTrue(TextInserter.isPasteboardCommitVisible(
            currentChangeCount: 12,
            expectedChangeCount: 12,
            currentString: "dictated",
            expectedText: "dictated"
        ))
        XCTAssertFalse(TextInserter.isPasteboardCommitVisible(
            currentChangeCount: 11,
            expectedChangeCount: 12,
            currentString: "dictated",
            expectedText: "dictated"
        ))
        XCTAssertFalse(TextInserter.isPasteboardCommitVisible(
            currentChangeCount: 12,
            expectedChangeCount: 12,
            currentString: "old",
            expectedText: "dictated"
        ))
    }

    func testClipboardRestoreDecisionRestoresAfterVerifiedPaste() {
        let decision = TextInserter.clipboardRestoreDecision(
            pasteOutcome: .succeeded,
            currentChangeCount: 7,
            insertionChangeCount: 7
        )
        XCTAssertEqual(decision, .restorePrevious)
    }

    func testClipboardRestoreDecisionLeavesDictatedTextAfterFailedPaste() {
        let decision = TextInserter.clipboardRestoreDecision(
            pasteOutcome: .failed,
            currentChangeCount: 7,
            insertionChangeCount: 7
        )
        XCTAssertEqual(decision, .keepDictatedText)
    }

    func testClipboardRestoreDecisionLeavesDictatedTextAfterUnverifiedPaste() {
        let decision = TextInserter.clipboardRestoreDecision(
            pasteOutcome: .unverified,
            currentChangeCount: 7,
            insertionChangeCount: 7
        )
        XCTAssertEqual(decision, .keepDictatedText)
    }

    func testClipboardRestoreDecisionDoesNotOverwriteUserClipboardChange() {
        let decision = TextInserter.clipboardRestoreDecision(
            pasteOutcome: .succeeded,
            currentChangeCount: 8,
            insertionChangeCount: 7
        )
        XCTAssertEqual(decision, .leaveCurrentClipboardUntouched)
    }

    func testPlainPasteMenuTitleExcludesOtherPasteCommands() {
        XCTAssertTrue(TextInserter.isPlainPasteMenuTitle("Paste"))
        XCTAssertTrue(TextInserter.isPlainPasteMenuTitle(" Paste "))
        XCTAssertFalse(TextInserter.isPlainPasteMenuTitle("Paste and Match Style"))
        XCTAssertFalse(TextInserter.isPlainPasteMenuTitle("Paste Item"))
    }

    func testPlainPasteMenuShortcutMatchesCommandVOnly() {
        XCTAssertTrue(TextInserter.isPlainPasteMenuShortcut(commandCharacter: "v", modifiers: 0))
        XCTAssertTrue(TextInserter.isPlainPasteMenuShortcut(commandCharacter: "V", modifiers: 0))
        XCTAssertFalse(TextInserter.isPlainPasteMenuShortcut(commandCharacter: "v", modifiers: 1))
        XCTAssertFalse(TextInserter.isPlainPasteMenuShortcut(commandCharacter: "v", modifiers: 8))
        XCTAssertFalse(TextInserter.isPlainPasteMenuShortcut(commandCharacter: "c", modifiers: 0))
    }

    func testSafeModeSanitizationPreservesTabsAndSpacesButRemovesNewlines() {
        let text = " leading\ttext\nnext line\r\nfinal "

        XCTAssertEqual(
            AppStateManager.sanitizeForInsertion(text, safeModeEnabled: true),
            " leading\ttext next line  final "
        )
        XCTAssertEqual(AppStateManager.sanitizeForInsertion(text, safeModeEnabled: false), text)
    }
}
