import XCTest
@testable import KotaebaApp

final class HotkeyProcessorTests: XCTestCase {
    private let xKeyCode = Constants.Hotkey.defaultKeyCode
    private let escapeKeyCode: UInt16 = 53

    func testHoldModeStartsOnKeyDownAndStopsOnKeyUp() {
        var processor = makeProcessor()

        let start = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        XCTAssertEqual(start.actions, [.startRecording])
        XCTAssertTrue(start.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .holdRecording(startedAt: 1.0))

        let stop = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.5),
            recordingMode: .hold
        )
        XCTAssertEqual(stop.actions, [.stopRecording])
        XCTAssertTrue(stop.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testHoldModeIgnoresKeyRepeatWhileRecording() {
        var processor = makeProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )

        let repeatResult = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, isRepeat: true, timestamp: 1.1),
            recordingMode: .hold
        )

        XCTAssertEqual(repeatResult.actions, [])
        XCTAssertTrue(repeatResult.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .holdRecording(startedAt: 1.0))
    }

    func testExtraModifiersDoNotTrigger() {
        var processor = makeProcessor()

        let shifted = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: [.control, .shift], timestamp: 1.0),
            recordingMode: .hold
        )
        XCTAssertEqual(shifted.actions, [])
        XCTAssertFalse(shifted.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)

        let cleanPress = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 2.0),
            recordingMode: .hold
        )
        XCTAssertEqual(cleanPress.actions, [.startRecording])
    }

    func testControlReleaseStopsHoldRecording() {
        var processor = makeProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )

        let releaseControl = processor.handle(
            .modifiersChanged(modifiers: [], timestamp: 1.5),
            recordingMode: .hold
        )

        XCTAssertEqual(releaseControl.actions, [.stopRecording])
        XCTAssertFalse(releaseControl.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testEscapeCancelsHoldRecordingAndReleaseDoesNotStopAgain() {
        var processor = makeProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )

        let cancel = processor.handle(
            .keyDown(keyCode: escapeKeyCode, modifiers: .control, timestamp: 1.2),
            recordingMode: .hold
        )
        XCTAssertEqual(cancel.actions, [.cancelRecording])
        XCTAssertTrue(cancel.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .cancelledWaitingForRelease)

        let release = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.4),
            recordingMode: .hold
        )
        XCTAssertEqual(release.actions, [])
        XCTAssertTrue(release.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testShortAccidentalTapCancelsInsteadOfStopping() {
        var processor = makeProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )

        let shortRelease = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.05),
            recordingMode: .hold
        )

        XCTAssertEqual(shortRelease.actions, [.cancelRecording])
        XCTAssertTrue(shortRelease.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .awaitingSecondTap(firstTapEndedAt: 1.05))
    }

    func testTapDisabledDuringHoldCancelsAndRequestsReenable() {
        var processor = makeProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )

        let disabled = processor.handle(.tapDisabled(timestamp: 1.3), recordingMode: .hold)
        XCTAssertEqual(disabled.actions, [.cancelRecording, .reenableEventTap])
        XCTAssertFalse(disabled.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .dirtyWaitingForRelease)

        let release = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.4),
            recordingMode: .hold
        )
        XCTAssertEqual(release.actions, [])
        XCTAssertTrue(release.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testHoldModeDoubleTapLocksAndNextPressReleaseStops() {
        var processor = makeProcessor()

        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        let firstRelease = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.05),
            recordingMode: .hold
        )
        XCTAssertEqual(firstRelease.actions, [.cancelRecording])
        XCTAssertEqual(processor.state, .awaitingSecondTap(firstTapEndedAt: 1.05))

        let secondDown = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.2),
            recordingMode: .hold
        )
        XCTAssertEqual(secondDown.actions, [.startRecording])
        XCTAssertTrue(secondDown.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .doubleTapRecording(startedAt: 1.2))

        let secondUp = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.25),
            recordingMode: .hold
        )
        XCTAssertEqual(secondUp.actions, [])
        XCTAssertTrue(secondUp.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .lockedRecording)

        let stopDown = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 3.0),
            recordingMode: .hold
        )
        XCTAssertEqual(stopDown.actions, [])
        XCTAssertTrue(stopDown.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .lockedStopKeyPressed)

        let stopUp = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 3.1),
            recordingMode: .hold
        )
        XCTAssertEqual(stopUp.actions, [.stopRecording])
        XCTAssertTrue(stopUp.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testDoubleTapTimingExpiryStartsANewHold() {
        var processor = makeProcessor()

        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        _ = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.05),
            recordingMode: .hold
        )

        let lateSecondDown = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.5),
            recordingMode: .hold
        )
        XCTAssertEqual(lateSecondDown.actions, [.startRecording])
        XCTAssertTrue(lateSecondDown.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .holdRecording(startedAt: 1.5))

        let release = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.8),
            recordingMode: .hold
        )
        XCTAssertEqual(release.actions, [.stopRecording])
        XCTAssertEqual(processor.state, .idle)
    }

    func testKeyRepeatDoesNotCountAsSecondTap() {
        var processor = makeProcessor()

        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        _ = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.05),
            recordingMode: .hold
        )

        let repeatResult = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, isRepeat: true, timestamp: 1.1),
            recordingMode: .hold
        )
        XCTAssertEqual(repeatResult.actions, [])
        XCTAssertTrue(repeatResult.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .awaitingSecondTap(firstTapEndedAt: 1.05))

        let secondDown = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.2),
            recordingMode: .hold
        )
        XCTAssertEqual(secondDown.actions, [.startRecording])
        XCTAssertEqual(processor.state, .doubleTapRecording(startedAt: 1.2))
    }

    func testUnrelatedKeyPressClearsPendingDoubleTap() {
        var processor = makeProcessor()

        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        _ = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.05),
            recordingMode: .hold
        )

        let unrelatedKey = processor.handle(
            .keyDown(keyCode: 49, modifiers: [], timestamp: 1.1),
            recordingMode: .hold
        )
        XCTAssertEqual(unrelatedKey.actions, [])
        XCTAssertFalse(unrelatedKey.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)

        let nextHotkey = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.2),
            recordingMode: .hold
        )
        XCTAssertEqual(nextHotkey.actions, [.startRecording])
        XCTAssertEqual(processor.state, .holdRecording(startedAt: 1.2))
    }

    func testEscapeCancelsLockedRecording() {
        var processor = makeLockedHoldProcessor()

        let cancel = processor.handle(
            .keyDown(keyCode: escapeKeyCode, modifiers: .control, timestamp: 2.0),
            recordingMode: .hold
        )

        XCTAssertEqual(cancel.actions, [.cancelRecording])
        XCTAssertTrue(cancel.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testTapDisabledDuringDoubleTapSequenceClearsPendingLock() {
        var processor = makeProcessor()

        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        _ = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.05),
            recordingMode: .hold
        )

        let disabled = processor.handle(.tapDisabled(timestamp: 1.1), recordingMode: .hold)

        XCTAssertEqual(disabled.actions, [.reenableEventTap])
        XCTAssertFalse(disabled.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testToggleModeLocksOnFirstPressAndStopsOnSecondPress() {
        var processor = makeProcessor()

        let firstDown = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .toggle
        )
        XCTAssertEqual(firstDown.actions, [])
        XCTAssertTrue(firstDown.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .toggleKeyPressed(wasLocked: false))

        let firstUp = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.1),
            recordingMode: .toggle
        )
        XCTAssertEqual(firstUp.actions, [.startRecording])
        XCTAssertTrue(firstUp.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .lockedRecording)

        let secondDown = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 2.0),
            recordingMode: .toggle
        )
        XCTAssertEqual(secondDown.actions, [])
        XCTAssertTrue(secondDown.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .toggleKeyPressed(wasLocked: true))

        let secondUp = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 2.1),
            recordingMode: .toggle
        )
        XCTAssertEqual(secondUp.actions, [.stopRecording])
        XCTAssertTrue(secondUp.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testTapDisabledWhileLockedCancelsAndRequestsReenable() {
        var processor = makeProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .toggle
        )
        _ = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.1),
            recordingMode: .toggle
        )

        let disabled = processor.handle(.tapDisabled(timestamp: 1.3), recordingMode: .toggle)

        XCTAssertEqual(disabled.actions, [.cancelRecording, .reenableEventTap])
        XCTAssertFalse(disabled.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testTapDisabledWhileLockedStopKeyPressedWaitsForRelease() {
        var processor = makeLockedHoldProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 2.0),
            recordingMode: .hold
        )

        let disabled = processor.handle(.tapDisabled(timestamp: 2.05), recordingMode: .hold)

        XCTAssertEqual(disabled.actions, [.cancelRecording, .reenableEventTap])
        XCTAssertFalse(disabled.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .dirtyWaitingForRelease)

        let release = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 2.1),
            recordingMode: .hold
        )

        XCTAssertEqual(release.actions, [])
        XCTAssertTrue(release.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testModifierReleaseWhileLockedStopKeyPressedWaitsForKeyRelease() {
        var processor = makeLockedHoldProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 2.0),
            recordingMode: .hold
        )

        let modifierRelease = processor.handle(
            .modifiersChanged(modifiers: [], timestamp: 2.05),
            recordingMode: .hold
        )

        XCTAssertEqual(modifierRelease.actions, [.stopRecording])
        XCTAssertFalse(modifierRelease.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .dirtyWaitingForRelease)

        let keyRelease = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: [], timestamp: 2.1),
            recordingMode: .hold
        )

        XCTAssertEqual(keyRelease.actions, [])
        XCTAssertTrue(keyRelease.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)
    }

    func testResetClearsPendingDoubleTapAndLockedRecordingState() {
        var pendingProcessor = makeProcessor()
        _ = pendingProcessor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        _ = pendingProcessor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.05),
            recordingMode: .hold
        )

        pendingProcessor.reset()

        XCTAssertEqual(pendingProcessor.state, .idle)

        var lockedProcessor = makeLockedHoldProcessor()

        lockedProcessor.reset()

        XCTAssertEqual(lockedProcessor.state, .idle)
    }

    func testCustomShortcutTriggersInsteadOfDefaultShortcut() {
        var processor = HotkeyProcessor(
            configuration: HotkeyShortcut(
                keyCode: 49,
                modifiers: [.control, .option]
            ).processorConfiguration
        )

        let defaultShortcut = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        XCTAssertEqual(defaultShortcut.actions, [])
        XCTAssertFalse(defaultShortcut.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .idle)

        let customShortcut = processor.handle(
            .keyDown(keyCode: 49, modifiers: [.control, .option], timestamp: 2.0),
            recordingMode: .hold
        )
        XCTAssertEqual(customShortcut.actions, [.startRecording])
        XCTAssertTrue(customShortcut.shouldConsumeEvent)
        XCTAssertEqual(processor.state, .holdRecording(startedAt: 2.0))
    }

    private func makeProcessor() -> HotkeyProcessor {
        HotkeyProcessor(
            configuration: HotkeyConfiguration(
                keyCode: xKeyCode,
                requiredModifiers: .control,
                escapeKeyCode: escapeKeyCode,
                minimumHoldDuration: 0.18,
                doubleTapLockWindow: 0.3
            )
        )
    }

    private func makeLockedHoldProcessor() -> HotkeyProcessor {
        var processor = makeProcessor()
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.0),
            recordingMode: .hold
        )
        _ = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.05),
            recordingMode: .hold
        )
        _ = processor.handle(
            .keyDown(keyCode: xKeyCode, modifiers: .control, timestamp: 1.2),
            recordingMode: .hold
        )
        _ = processor.handle(
            .keyUp(keyCode: xKeyCode, modifiers: .control, timestamp: 1.25),
            recordingMode: .hold
        )
        return processor
    }
}
