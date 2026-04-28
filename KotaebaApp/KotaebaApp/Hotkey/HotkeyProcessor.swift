import Foundation

struct HotkeyModifiers: OptionSet, Equatable {
    let rawValue: UInt32

    static let control = HotkeyModifiers(rawValue: 1 << 0)
    static let shift = HotkeyModifiers(rawValue: 1 << 1)
    static let option = HotkeyModifiers(rawValue: 1 << 2)
    static let command = HotkeyModifiers(rawValue: 1 << 3)
}

struct HotkeyConfiguration: Equatable {
    var keyCode: UInt16
    var requiredModifiers: HotkeyModifiers
    var escapeKeyCode: UInt16
    var minimumHoldDuration: TimeInterval

    static let `default` = HotkeyConfiguration(
        keyCode: Constants.Hotkey.defaultKeyCode,
        requiredModifiers: .control,
        escapeKeyCode: Constants.Hotkey.escapeKeyCode,
        minimumHoldDuration: Constants.Hotkey.minimumHoldDuration
    )
}

struct HotkeyProcessorInput: Equatable {
    enum Kind: Equatable {
        case keyDown
        case keyUp
        case modifiersChanged
        case tapDisabled
    }

    let kind: Kind
    let keyCode: UInt16?
    let modifiers: HotkeyModifiers
    let isRepeat: Bool
    let timestamp: TimeInterval

    static func keyDown(
        keyCode: UInt16,
        modifiers: HotkeyModifiers,
        isRepeat: Bool = false,
        timestamp: TimeInterval
    ) -> HotkeyProcessorInput {
        HotkeyProcessorInput(
            kind: .keyDown,
            keyCode: keyCode,
            modifiers: modifiers,
            isRepeat: isRepeat,
            timestamp: timestamp
        )
    }

    static func keyUp(
        keyCode: UInt16,
        modifiers: HotkeyModifiers,
        timestamp: TimeInterval
    ) -> HotkeyProcessorInput {
        HotkeyProcessorInput(
            kind: .keyUp,
            keyCode: keyCode,
            modifiers: modifiers,
            isRepeat: false,
            timestamp: timestamp
        )
    }

    static func modifiersChanged(
        modifiers: HotkeyModifiers,
        timestamp: TimeInterval
    ) -> HotkeyProcessorInput {
        HotkeyProcessorInput(
            kind: .modifiersChanged,
            keyCode: nil,
            modifiers: modifiers,
            isRepeat: false,
            timestamp: timestamp
        )
    }

    static func tapDisabled(timestamp: TimeInterval) -> HotkeyProcessorInput {
        HotkeyProcessorInput(
            kind: .tapDisabled,
            keyCode: nil,
            modifiers: [],
            isRepeat: false,
            timestamp: timestamp
        )
    }
}

struct HotkeyProcessorResult: Equatable {
    enum Action: Equatable {
        case startRecording
        case stopRecording
        case cancelRecording
        case reenableEventTap
    }

    var actions: [Action]
    var shouldConsumeEvent: Bool

    static let passThrough = HotkeyProcessorResult(actions: [], shouldConsumeEvent: false)
    static let consume = HotkeyProcessorResult(actions: [], shouldConsumeEvent: true)
}

struct HotkeyProcessor {
    enum State: Equatable {
        case idle
        case holdRecording(startedAt: TimeInterval)
        case toggleKeyPressed(wasLocked: Bool)
        case lockedRecording
        case cancelledWaitingForRelease
        case dirtyWaitingForRelease
    }

    private(set) var state: State = .idle
    var configuration: HotkeyConfiguration

    init(configuration: HotkeyConfiguration = .default) {
        self.configuration = configuration
    }

    mutating func reset() {
        state = .idle
    }

    mutating func handle(_ input: HotkeyProcessorInput, recordingMode: RecordingMode) -> HotkeyProcessorResult {
        switch input.kind {
        case .tapDisabled:
            return handleTapDisabled()
        case .modifiersChanged:
            return handleModifiersChanged(input)
        case .keyDown:
            return handleKeyDown(input, recordingMode: recordingMode)
        case .keyUp:
            return handleKeyUp(input, recordingMode: recordingMode)
        }
    }

    private mutating func handleTapDisabled() -> HotkeyProcessorResult {
        switch state {
        case .holdRecording:
            state = .dirtyWaitingForRelease
            return HotkeyProcessorResult(actions: [.cancelRecording, .reenableEventTap], shouldConsumeEvent: false)
        case .toggleKeyPressed:
            state = .dirtyWaitingForRelease
            return HotkeyProcessorResult(actions: [.reenableEventTap], shouldConsumeEvent: false)
        case .cancelledWaitingForRelease, .dirtyWaitingForRelease:
            return HotkeyProcessorResult(actions: [.reenableEventTap], shouldConsumeEvent: false)
        case .idle, .lockedRecording:
            return HotkeyProcessorResult(actions: [.reenableEventTap], shouldConsumeEvent: false)
        }
    }

    private mutating func handleModifiersChanged(_ input: HotkeyProcessorInput) -> HotkeyProcessorResult {
        if requiredModifiersAreReleased(input.modifiers) {
            switch state {
            case .holdRecording(let startedAt):
                state = .idle
                return completionResult(startedAt: startedAt, endedAt: input.timestamp, shouldConsumeEvent: false)
            case .toggleKeyPressed:
                state = .idle
                return .passThrough
            case .cancelledWaitingForRelease, .dirtyWaitingForRelease:
                state = .idle
                return .passThrough
            case .idle, .lockedRecording:
                return .passThrough
            }
        }

        return .passThrough
    }

    private mutating func handleKeyDown(
        _ input: HotkeyProcessorInput,
        recordingMode: RecordingMode
    ) -> HotkeyProcessorResult {
        guard let keyCode = input.keyCode else { return .passThrough }

        if keyCode == configuration.escapeKeyCode {
            return handleEscapeKeyDown()
        }

        guard keyCode == configuration.keyCode else {
            return .passThrough
        }

        guard exactRequiredModifiersArePressed(input.modifiers) else {
            return .passThrough
        }

        if input.isRepeat {
            return consumesTargetKeyWhileActive ? .consume : .passThrough
        }

        switch recordingMode {
        case .hold:
            switch state {
            case .idle:
                state = .holdRecording(startedAt: input.timestamp)
                return HotkeyProcessorResult(actions: [.startRecording], shouldConsumeEvent: true)
            case .holdRecording, .cancelledWaitingForRelease, .dirtyWaitingForRelease:
                return .consume
            case .toggleKeyPressed, .lockedRecording:
                state = .holdRecording(startedAt: input.timestamp)
                return HotkeyProcessorResult(actions: [.startRecording], shouldConsumeEvent: true)
            }
        case .toggle:
            switch state {
            case .idle:
                state = .toggleKeyPressed(wasLocked: false)
                return .consume
            case .lockedRecording:
                state = .toggleKeyPressed(wasLocked: true)
                return .consume
            case .toggleKeyPressed, .holdRecording, .cancelledWaitingForRelease, .dirtyWaitingForRelease:
                return .consume
            }
        }
    }

    private mutating func handleKeyUp(
        _ input: HotkeyProcessorInput,
        recordingMode: RecordingMode
    ) -> HotkeyProcessorResult {
        guard input.keyCode == configuration.keyCode else {
            return .passThrough
        }

        switch state {
        case .holdRecording(let startedAt):
            state = .idle
            return completionResult(startedAt: startedAt, endedAt: input.timestamp, shouldConsumeEvent: true)
        case .toggleKeyPressed(let wasLocked):
            if recordingMode == .toggle {
                state = wasLocked ? .idle : .lockedRecording
                let action: HotkeyProcessorResult.Action = wasLocked ? .stopRecording : .startRecording
                return HotkeyProcessorResult(actions: [action], shouldConsumeEvent: true)
            }
            state = .idle
            return .consume
        case .cancelledWaitingForRelease, .dirtyWaitingForRelease:
            state = .idle
            return .consume
        case .idle:
            return exactRequiredModifiersArePressed(input.modifiers) ? .consume : .passThrough
        case .lockedRecording:
            return .consume
        }
    }

    private mutating func handleEscapeKeyDown() -> HotkeyProcessorResult {
        switch state {
        case .holdRecording:
            state = .cancelledWaitingForRelease
            return HotkeyProcessorResult(actions: [.cancelRecording], shouldConsumeEvent: true)
        case .lockedRecording:
            state = .idle
            return HotkeyProcessorResult(actions: [.cancelRecording], shouldConsumeEvent: true)
        case .toggleKeyPressed:
            state = .cancelledWaitingForRelease
            return .consume
        case .cancelledWaitingForRelease, .dirtyWaitingForRelease:
            return .consume
        case .idle:
            return .passThrough
        }
    }

    private func completionResult(
        startedAt: TimeInterval,
        endedAt: TimeInterval,
        shouldConsumeEvent: Bool
    ) -> HotkeyProcessorResult {
        let duration = max(0, endedAt - startedAt)
        let action: HotkeyProcessorResult.Action = duration < configuration.minimumHoldDuration
            ? .cancelRecording
            : .stopRecording
        return HotkeyProcessorResult(actions: [action], shouldConsumeEvent: shouldConsumeEvent)
    }

    private var consumesTargetKeyWhileActive: Bool {
        switch state {
        case .holdRecording, .toggleKeyPressed, .lockedRecording, .cancelledWaitingForRelease, .dirtyWaitingForRelease:
            return true
        case .idle:
            return false
        }
    }

    private func exactRequiredModifiersArePressed(_ modifiers: HotkeyModifiers) -> Bool {
        modifiers == configuration.requiredModifiers
    }

    private func requiredModifiersAreReleased(_ modifiers: HotkeyModifiers) -> Bool {
        !modifiers.isSuperset(of: configuration.requiredModifiers)
    }
}
