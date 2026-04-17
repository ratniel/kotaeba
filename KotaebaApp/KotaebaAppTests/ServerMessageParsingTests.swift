import XCTest
@testable import KotaebaApp

final class ServerMessageParsingTests: XCTestCase {
    func testTranscriptionMessageParsing() throws {
        let json = """
        {"text":"hello world","segments":[],"is_partial":false,"language":"en","confidence":0.92}
        """

        let message = ServerMessage(from: json)
        switch message {
        case .transcription(let transcription):
            XCTAssertEqual(transcription.text, "hello world")
            XCTAssertEqual(transcription.isPartial, false)
            XCTAssertEqual(transcription.language, "en")
            XCTAssertEqual(transcription.confidence, 0.92)
        default:
            XCTFail("Expected transcription message")
        }
    }

    func testStatusMessageParsing() {
        let json = """
        {"status":"ready","message":"Ready to transcribe","timestamp":"2025-01-01T00:00:00Z","progress":1.0}
        """

        let message = ServerMessage(from: json)
        switch message {
        case .status(let status):
            XCTAssertEqual(status.status, "ready")
            XCTAssertEqual(status.message, "Ready to transcribe")
            XCTAssertEqual(status.timestamp, "2025-01-01T00:00:00Z")
            XCTAssertEqual(status.progress, 1.0)
        default:
            XCTFail("Expected status message")
        }
    }

    func testUnknownMessageParsing() {
        let json = """
        {"foo":"bar"}
        """

        let message = ServerMessage(from: json)
        switch message {
        case .unknown(let raw):
            XCTAssertTrue(raw.contains("foo"))
        default:
            XCTFail("Expected unknown message")
        }
    }
}
