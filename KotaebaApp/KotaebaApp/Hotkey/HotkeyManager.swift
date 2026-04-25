import Carbon
import Cocoa
import Foundation

/// Delegate protocol for hotkey events
protocol HotkeyManagerDelegate: AnyObject {
    /// Called when hotkey triggers start (key down in hold mode, key up in toggle mode)
    func hotkeyDidTriggerStart()
    
    /// Called when hotkey triggers stop (key up in hold mode only)
    func hotkeyDidTriggerStop()

    /// Called when the current recording should be cancelled and discarded
    func hotkeyDidCancelRecording()
}

/// Manages global hotkey listening for recording control
///
/// Default hotkey: Ctrl+X
/// Supports two modes:
/// - Hold (Push-to-Talk): Record while key is held
/// - Toggle: Press to start, press again to stop
class HotkeyManager {
    
    // MARK: - Properties
    
    weak var delegate: HotkeyManagerDelegate?
    
    var recordingMode: RecordingMode = .hold {
        didSet {
            processor.reset()
        }
    }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var processor: HotkeyProcessor
    private var shortcut: HotkeyShortcut
    private(set) var isRunning = false

    init(shortcut: HotkeyShortcut = .default) {
        self.shortcut = shortcut
        processor = HotkeyProcessor(configuration: shortcut.processorConfiguration)
    }
    
    // MARK: - Lifecycle
    
    deinit {
        stop()
    }
    
    // MARK: - Public API
    
    /// Start listening for hotkey events
    /// Returns true if successful, false if permissions are missing
    func start(promptIfMissing: Bool = false) -> Bool {
        if isRunning {
            Log.hotkey.debug("Event tap already running")
            return true
        }

        guard PermissionManager.checkAccessibilityPermission() else {
            Log.hotkey.error("Accessibility permission not granted")
            if promptIfMissing {
                _ = PermissionManager.requestAccessibilityPermission()
            }
            return false
        }
        
        // Event types to capture: keyDown, keyUp, flagsChanged
        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        
        // Create event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.hotkey.error("Failed to create event tap")
            return false
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        
        Log.hotkey.info("Event tap started - listening for \(shortcut.displayString)")
        return true
    }
    
    /// Stop listening for hotkey events
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        processor.reset()
        Log.hotkey.info("Event tap stopped")
    }
    
    /// Update the hotkey configuration
    func setHotkey(_ shortcut: HotkeyShortcut) {
        self.shortcut = shortcut
        processor.configuration = shortcut.processorConfiguration
        processor.reset()
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let result = processor.handle(
            processorInput(for: type, event: event),
            recordingMode: recordingMode
        )
        dispatch(result.actions)
        return result.shouldConsumeEvent ? nil : Unmanaged.passUnretained(event)
    }

    private func processorInput(for type: CGEventType, event: CGEvent) -> HotkeyProcessorInput {
        let timestamp = TimeInterval(event.timestamp) / 1_000_000_000
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .tapDisabled(timestamp: timestamp)
        case .flagsChanged:
            return .modifiersChanged(
                modifiers: HotkeyModifiers(eventFlags: event.flags),
                timestamp: timestamp
            )
        case .keyDown:
            return .keyDown(
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                modifiers: HotkeyModifiers(eventFlags: event.flags),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                timestamp: timestamp
            )
        case .keyUp:
            return .keyUp(
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                modifiers: HotkeyModifiers(eventFlags: event.flags),
                timestamp: timestamp
            )
        default:
            return .modifiersChanged(
                modifiers: HotkeyModifiers(eventFlags: event.flags),
                timestamp: timestamp
            )
        }
    }

    private func dispatch(_ actions: [HotkeyProcessorResult.Action]) {
        for action in actions {
            switch action {
            case .startRecording:
                Log.hotkey.debug("Start action emitted (mode: \(recordingMode))")
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidTriggerStart()
                }
            case .stopRecording:
                Log.hotkey.debug("Stop action emitted (mode: \(recordingMode))")
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidTriggerStop()
                }
            case .cancelRecording:
                Log.hotkey.debug("Cancel action emitted (mode: \(recordingMode))")
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidCancelRecording()
                }
            case .reenableEventTap:
                if let tap = eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }
    }
}

private extension HotkeyModifiers {
    init(eventFlags: CGEventFlags) {
        var modifiers: HotkeyModifiers = []
        if eventFlags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if eventFlags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if eventFlags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if eventFlags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        self = modifiers
    }
}
