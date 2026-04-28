import XCTest
@testable import KotaebaApp

final class ShellCommandRunnerTests: XCTestCase {
    func testRetainsOnlyElevatedLinesInPrimaryBuffers() {
        let state = CommandOutputState()

        state.append("download 10%\nWARNING: using fallback cache\n", stream: .standardOutput)
        state.append("progress 20%\nERROR: backend unavailable\n", stream: .standardError)

        XCTAssertEqual(state.capturedOutput, "WARNING: using fallback cache\n")
        XCTAssertEqual(state.capturedError, "ERROR: backend unavailable\n")
    }

    func testDiagnosticMessageFallsBackToTailWhenNoElevatedLinesExist() {
        let state = CommandOutputState()

        state.append("loading model metadata\nplain failure explanation without keywords\n", stream: .standardError)

        XCTAssertEqual(state.capturedError, "")
        XCTAssertEqual(state.diagnosticMessage, state.errorTail)
        XCTAssertTrue(state.diagnosticMessage.contains("plain failure explanation without keywords"))
    }

    func testBuffersStayWithinConfiguredLimits() {
        let state = CommandOutputState()
        let longWarning = String(repeating: "W", count: CommandOutputState.elevatedCharacterLimit + 256)
        let longInfo = String(repeating: "i", count: CommandOutputState.tailCharacterLimit + 256)

        state.append("WARNING: \(longWarning)\n", stream: .standardOutput)
        state.append(longInfo, stream: .standardError)

        XCTAssertLessThanOrEqual(state.capturedOutput.count, CommandOutputState.elevatedCharacterLimit)
        XCTAssertLessThanOrEqual(state.errorTail.count, CommandOutputState.tailCharacterLimit)
        XCTAssertTrue(state.capturedOutput.hasSuffix(String(repeating: "W", count: 32) + "\n"))
        XCTAssertTrue(state.errorTail.hasSuffix(String(repeating: "i", count: 32)))
    }

    func testDiagnosticMessagePrefersElevatedErrorOverFallbackTail() {
        let state = CommandOutputState()

        state.append("informational output\n", stream: .standardOutput)
        state.append("Traceback (most recent call last):\nValueError: bad model\n", stream: .standardError)

        XCTAssertEqual(
            state.diagnosticMessage,
            "Traceback (most recent call last):\nValueError: bad model\n"
        )
    }
}
