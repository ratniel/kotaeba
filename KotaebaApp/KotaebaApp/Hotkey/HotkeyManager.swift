import Carbon
import Cocoa
import Foundation

/// Delegate protocol for hotkey events
protocol HotkeyManagerDelegate: AnyObject {
    /// Called when hotkey triggers start (key down in hold mode, key up in toggle mode)
    func hotkeyDidTriggerStart()
    
    /// Called when hotkey triggers stop (key up in hold mode only)
    func hotkeyDidTriggerStop()
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
    
    var recordingMode: RecordingMode = .hold
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyPressed = false
    
    // Hotkey configuration: Ctrl + X
    private var targetKeyCode: CGKeyCode = CGKeyCode(Constants.Hotkey.defaultKeyCode)
    private let controlModifierMask: CGEventFlags = .maskControl
    
    // MARK: - Lifecycle
    
    deinit {
        stop()
    }
    
    // MARK: - Public API
    
    /// Start listening for hotkey events
    /// Returns true if successful, false if permissions are missing
    func start() -> Bool {
        guard PermissionManager.checkAccessibilityPermission() else {
            Log.hotkey.error("Accessibility permission not granted")
            PermissionManager.requestAccessibilityPermission()
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
                    return Unmanaged.passRetained(event)
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
        
        Log.hotkey.info("Event tap started - listening for Ctrl+X")
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
        Log.hotkey.info("Event tap stopped")
    }
    
    /// Update the hotkey configuration
    func setHotkey(keyCode: CGKeyCode) {
        targetKeyCode = keyCode
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled (system can disable taps under heavy load)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Check if Control is pressed (and not Cmd, Option, or Shift)
        let isControlPressed = flags.contains(.maskControl)
        let isOtherModifiers = flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskShift)
        let isTargetKey = keyCode == targetKeyCode
        
        // Only handle if it's our hotkey (Ctrl+X with no other modifiers)
        guard isTargetKey && isControlPressed && !isOtherModifiers else {
            return Unmanaged.passRetained(event)
        }
        
        switch type {
        case .keyDown:
            handleKeyDown()
            return nil  // Consume the event (don't pass to other apps)
            
        case .keyUp:
            handleKeyUp()
            return nil  // Consume the event
            
        default:
            return Unmanaged.passRetained(event)
        }
    }
    
    private func handleKeyDown() {
        // Ignore key repeat (when holding key)
        guard !isHotkeyPressed else { return }
        isHotkeyPressed = true
        
        Log.hotkey.debug("Key down (mode: \(recordingMode))")
        
        switch recordingMode {
        case .hold:
            // Push-to-Talk: Start recording on key down
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidTriggerStart()
            }
            
        case .toggle:
            // Toggle mode: Do nothing on key down, wait for key up
            break
        }
    }
    
    private func handleKeyUp() {
        guard isHotkeyPressed else { return }
        isHotkeyPressed = false
        
        Log.hotkey.debug("Key up (mode: \(recordingMode))")
        
        switch recordingMode {
        case .hold:
            // Push-to-Talk: Stop recording on key up
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidTriggerStop()
            }
            
        case .toggle:
            // Toggle mode: Toggle state on key up (cleaner than key down)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidTriggerStart()
            }
        }
    }
}
