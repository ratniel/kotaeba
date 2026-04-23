import XCTest
import AppKit
@testable import KotaebaApp

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
}
