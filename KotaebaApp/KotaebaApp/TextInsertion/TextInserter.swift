import Carbon
import Cocoa
import Foundation
import ApplicationServices

enum TextInsertionMethod: String {
    case accessibility = "Accessibility API"
    case unicodeEvent = "Unicode CGEvent"
    case clipboard = "Clipboard Paste"
}

enum TextInsertionError: LocalizedError, Equatable {
    case emptyText
    case accessibilityPermissionDenied
    case noFocusedElement
    case accessibilityInsertFailed
    case secureInputEnabled
    case unicodeEventFailed
    case clipboardFallbackDisabled
    case clipboardSetFailed

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Empty text cannot be inserted."
        case .accessibilityPermissionDenied:
            return "Accessibility permission is not granted."
        case .noFocusedElement:
            return "No focused text field found."
        case .accessibilityInsertFailed:
            return "Accessibility insertion failed."
        case .secureInputEnabled:
            return "Secure input is enabled. Text insertion is blocked by the system."
        case .unicodeEventFailed:
            return "Unicode event insertion failed."
        case .clipboardFallbackDisabled:
            return "Clipboard fallback is disabled in settings."
        case .clipboardSetFailed:
            return "Failed to write text to the clipboard."
        }
    }
}

enum TextInsertionResult: Equatable {
    case success(method: TextInsertionMethod)
    case failure(TextInsertionError)
}

/// Inserts text at the current cursor position in any application
///
/// Primary method: CGEvent with Unicode string (fast, supports unicode)
/// Fallback method: Clipboard + Cmd+V paste (more compatible, but modifies clipboard)
class TextInserter {
    
    // MARK: - Properties
    
    // MARK: - Public Methods
    
    /// Insert text at the current cursor position
    @discardableResult
    func insertText(_ text: String, promptIfMissing: Bool = false) -> TextInsertionResult {
        guard !text.isEmpty else {
            Log.textInsertion.warning("Attempted to insert empty text")
            return .failure(.emptyText)
        }
        
        guard PermissionManager.checkAccessibilityPermission() else {
            Log.textInsertion.error("Accessibility permission required")
            if promptIfMissing {
                _ = PermissionManager.requestAccessibilityPermission()
            }
            return .failure(.accessibilityPermissionDenied)
        }
        
        #if DEBUG
        Log.textInsertion.info("Inserting text: \"\(text)\"")
        #else
        Log.textInsertion.info("Inserting text (\(text.count) chars)")
        #endif
        Log.textInsertion.debug("Current app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown")")
        
        // Method 1: Accessibility API (best for secure input / system-wide)
        switch insertUsingAccessibility(text) {
        case .success:
            Log.textInsertion.info("Accessibility insert succeeded")
            return .success(method: .accessibility)
        case .failure(let error):
            if error == .noFocusedElement {
                Log.textInsertion.debug("No focused element found for accessibility insert")
            } else {
                Log.textInsertion.debug("Accessibility insert failed: \(error.localizedDescription)")
            }
        }
        
        // If secure input is enabled, CGEvent-based methods won't work
        if IsSecureEventInputEnabled() {
            Log.textInsertion.warning("Secure input is enabled; skipping CGEvent insertion methods")
            return .failure(.secureInputEnabled)
        }

        // Method 2: Unicode CGEvent (fast when the target exposes readable text state)
        if insertUsingUnicodeEvent(text) {
            Log.textInsertion.info("Unicode event insert succeeded")
            return .success(method: .unicodeEvent)
        }
        
        let allowClipboardFallback = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.useClipboardFallback)
        if allowClipboardFallback {
            Log.textInsertion.warning("Unicode event failed, trying clipboard fallback")
            if insertUsingClipboard(text) {
                return .success(method: .clipboard)
            }
            return .failure(.clipboardSetFailed)
        } else {
            Log.textInsertion.warning("Unicode event failed; clipboard fallback disabled in settings")
            return .failure(.clipboardFallbackDisabled)
        }
    }
    
    // MARK: - Method 1: CGEvent Unicode (Preferred)
    
    /// Insert text using CGEvent with Unicode string
    /// This is fast and supports unicode characters
    private func insertUsingUnicodeEvent(_ text: String) -> Bool {
        guard let snapshot = focusedTextSnapshot() else {
            Log.textInsertion.debug("Cannot verify Unicode event insertion because focused text state is unavailable")
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)
        
        // Convert string to UTF-16 code units
        var unicodeChars = Array(text.utf16)
        
        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            Log.textInsertion.error("Failed to create key down event")
            return false
        }
        
        // Set the unicode string on the event
        keyDown.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)
        
        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            Log.textInsertion.error("Failed to create key up event")
            return false
        }
        
        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return verifyInsertion(text: text, snapshot: snapshot)
    }
    
    // MARK: - Method 2: Clipboard + Paste (Fallback)
    
    /// Insert text using clipboard and simulated Cmd+V
    /// More compatible but temporarily modifies clipboard
    private func insertUsingClipboard(_ text: String) -> Bool {
        #if DEBUG
        Log.textInsertion.info("Using clipboard fallback for: \"\(text)\"")
        #else
        Log.textInsertion.info("Using clipboard fallback (\(text.count) chars)")
        #endif
        
        let pasteboard = NSPasteboard.general
        
        // Save current clipboard contents, including non-string representations.
        let previousContents = PasteboardSnapshot(items: Self.clonePasteboardItems(pasteboard.pasteboardItems))
        
        // Set our text to clipboard
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        let insertionChangeCount = pasteboard.changeCount
        Log.textInsertion.info("Set clipboard contents: \(success ? "success" : "failure")")
        guard success else { return false }
        
        // Simulate Cmd+V
        simulatePaste()
        
        // Restore previous clipboard after paste has had a chance to consume it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard pasteboard.changeCount == insertionChangeCount else {
                Log.textInsertion.debug("Skipping clipboard restore because clipboard changed after insertion")
                return
            }

            pasteboard.clearContents()
            if !previousContents.items.isEmpty {
                pasteboard.writeObjects(previousContents.items)
            }
            Log.textInsertion.debug("Restored previous clipboard")
        }

        return true
    }
    
    /// Simulate Cmd+V keystroke
    private func simulatePaste() {
        Log.textInsertion.debug("Simulating Cmd+V paste")
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key code 9 = 'v'
        let vKeyCode: CGKeyCode = 9
        
        // Small delay to ensure clipboard is set
        usleep(50000)  // 50ms
        
        // Key down with Command modifier
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            Log.textInsertion.debug("Cmd+V keyDown posted")
        } else {
            Log.textInsertion.error("Failed to create keyDown event")
        }
        
        // Small delay between keydown and keyup
        usleep(10000)  // 10ms
        
        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
            Log.textInsertion.debug("Cmd+V keyUp posted")
        } else {
            Log.textInsertion.error("Failed to create keyUp event")
        }
        
        Log.textInsertion.info("Paste simulation complete")
    }

    // MARK: - Method 0: Accessibility API (Most Reliable)

    /// Insert text using Accessibility APIs.
    /// This avoids CGEvent and works even when Secure Input is enabled.
    private func insertUsingAccessibility(_ text: String) -> Result<Void, TextInsertionError> {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusedResult == .success, let focusedRef else {
            Log.textInsertion.debug("No focused UI element available for accessibility insert")
            return .failure(.noFocusedElement)
        }
        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)
        // Try setting selected text directly (replaces current selection)
        if isAttributeSettable(element, attribute: kAXSelectedTextAttribute) {
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            if result == .success {
                return .success(())
            }
        }

        // Fallback: update value with current selection range
        guard let currentValue = copyStringAttribute(element, attribute: kAXValueAttribute) else {
            return .failure(.accessibilityInsertFailed)
        }

        guard let range = copySelectedRange(element) else {
            Log.textInsertion.debug("Focused element exposes a value but no selected text range")
            return .failure(.accessibilityInsertFailed)
        }
        let newValue = Self.applyInsertion(text: text, to: currentValue, range: range)

        guard isAttributeSettable(element, attribute: kAXValueAttribute) else {
            return .failure(.accessibilityInsertFailed)
        }

        let setValueResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFString)
        if setValueResult != .success {
            return .failure(.accessibilityInsertFailed)
        }

        if isAttributeSettable(element, attribute: kAXSelectedTextRangeAttribute) {
            var newRange = CFRange(location: range.location + text.utf16.count, length: 0)
            if let rangeValue = AXValueCreate(.cfRange, &newRange) {
                _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
            }
        }

        return .success(())
    }

    private struct FocusedTextSnapshot {
        let element: AXUIElement
        let value: String
        let selectedRange: CFRange
    }

    private struct PasteboardSnapshot {
        let items: [NSPasteboardItem]
    }

    private func focusedTextSnapshot() -> FocusedTextSnapshot? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusedResult == .success, let focusedRef else {
            return nil
        }

        let element = unsafeBitCast(focusedRef, to: AXUIElement.self)
        guard let value = copyStringAttribute(element, attribute: kAXValueAttribute),
              let selectedRange = copySelectedRange(element) else {
            return nil
        }

        return FocusedTextSnapshot(element: element, value: value, selectedRange: selectedRange)
    }

    private func verifyInsertion(text: String, snapshot: FocusedTextSnapshot) -> Bool {
        let expectedValue = Self.applyInsertion(text: text, to: snapshot.value, range: snapshot.selectedRange)

        for _ in 0..<10 {
            usleep(20000)
            if copyStringAttribute(snapshot.element, attribute: kAXValueAttribute) == expectedValue {
                return true
            }
        }

        Log.textInsertion.debug("Unicode event insertion could not be verified")
        return false
    }

    private func isAttributeSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    private func copyStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        if result == .success {
            if let value = valueRef as? String {
                return value
            }
            if let value = valueRef as? NSAttributedString {
                return value.string
            }
        }
        return nil
    }

    private func copySelectedRange(_ element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard result == .success, let rangeRef else {
            return nil
        }
        let rangeValue = unsafeBitCast(rangeRef, to: AXValue.self)

        var range = CFRange()
        if AXValueGetValue(rangeValue, .cfRange, &range) {
            return range
        }
        return nil
    }

    static func applyInsertion(text: String, to currentValue: String, range: CFRange) -> String {
        let utf16 = currentValue.utf16
        guard let start = utf16.index(utf16.startIndex, offsetBy: max(range.location, 0), limitedBy: utf16.endIndex),
              let end = utf16.index(start, offsetBy: max(range.length, 0), limitedBy: utf16.endIndex),
              let startIndex = String.Index(start, within: currentValue),
              let endIndex = String.Index(end, within: currentValue) else {
            return currentValue + text
        }

        var updated = currentValue
        updated.replaceSubrange(startIndex..<endIndex, with: text)
        return updated
    }

    static func clonePasteboardItems(_ items: [NSPasteboardItem]?) -> [NSPasteboardItem] {
        items?.map { item in
            let clonedItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    clonedItem.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    clonedItem.setString(string, forType: type)
                }
            }
            return clonedItem
        } ?? []
    }
    
    // MARK: - (Reserved for future insertion strategies)
}
