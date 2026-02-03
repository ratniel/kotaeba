import Carbon
import Cocoa
import Foundation
import ApplicationServices

/// Inserts text at the current cursor position in any application
///
/// Primary method: CGEvent with Unicode string (fast, supports unicode)
/// Fallback method: Clipboard + Cmd+V paste (more compatible, but modifies clipboard)
class TextInserter {
    
    // MARK: - Properties
    
    /// Whether to use clipboard fallback for incompatible apps
    var useClipboardFallback: Bool = false
    
    // MARK: - Public Methods
    
    /// Insert text at the current cursor position
    func insertText(_ text: String) {
        guard !text.isEmpty else {
            print("[TextInserter] ⚠️ Attempted to insert empty text")
            return
        }
        
        guard AXIsProcessTrusted() else {
            print("[TextInserter] ❌ Accessibility permission required")
            return
        }
        
        print("[TextInserter] 📝 Inserting text: \"\(text)\"")
        print("[TextInserter] 🔍 Current app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown")")
        
        // Try primary method first
        if insertUsingUnicodeEvent(text) {
            print("[TextInserter] ✅ Unicode event method succeeded")
            return
        }
        
        print("[TextInserter] ⚠️ Unicode event method failed, trying clipboard fallback...")
        
        // Fallback to clipboard method (always try, not just when enabled)
        insertUsingClipboard(text)
    }
    
    // MARK: - Method 1: CGEvent Unicode (Preferred)
    
    /// Insert text using CGEvent with Unicode string
    /// This is fast and supports unicode characters
    private func insertUsingUnicodeEvent(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Convert string to UTF-16 code units
        var unicodeChars = Array(text.utf16)
        
        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            print("[TextInserter] Failed to create key down event")
            return false
        }
        
        // Set the unicode string on the event
        keyDown.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)
        
        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            print("[TextInserter] Failed to create key up event")
            return false
        }
        
        // Post the events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        return true
    }
    
    // MARK: - Method 2: Clipboard + Paste (Fallback)
    
    /// Insert text using clipboard and simulated Cmd+V
    /// More compatible but temporarily modifies clipboard
    private func insertUsingClipboard(_ text: String) {
        print("[TextInserter] 📋 Using clipboard fallback for: \"\(text)\"")
        
        let pasteboard = NSPasteboard.general
        
        // Save current clipboard contents
        let previousContents = pasteboard.string(forType: .string)
        
        // Set our text to clipboard
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        print("[TextInserter] 📋 Set clipboard contents: \(success ? "✅" : "❌")")
        
        // Simulate Cmd+V
        simulatePaste()
        
        // Restore previous clipboard after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
                print("[TextInserter] 📋 Restored previous clipboard")
            }
        }
    }
    
    /// Simulate Cmd+V keystroke
    private func simulatePaste() {
        print("[TextInserter] ⌨️ Simulating Cmd+V paste...")
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key code 9 = 'v'
        let vKeyCode: CGKeyCode = 9
        
        // Small delay to ensure clipboard is set
        usleep(50000)  // 50ms
        
        // Key down with Command modifier
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            print("[TextInserter] ⌨️ Cmd+V keyDown posted")
        } else {
            print("[TextInserter] ❌ Failed to create keyDown event")
        }
        
        // Small delay between keydown and keyup
        usleep(10000)  // 10ms
        
        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
            print("[TextInserter] ⌨️ Cmd+V keyUp posted")
        } else {
            print("[TextInserter] ❌ Failed to create keyUp event")
        }
        
        print("[TextInserter] ✅ Paste simulation complete")
    }
    
    // MARK: - Method 3: Character-by-character (Slowest, ASCII only)
    
    /// Insert text character by character (for reference, not recommended)
    /// This is very slow and only works for basic ASCII
    private func insertCharacterByCharacter(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            guard let keyCode = keyCodeForCharacter(char) else { continue }
            
            let needsShift = char.isUppercase || shiftCharacters.contains(char)
            let flags: CGEventFlags = needsShift ? .maskShift : []
            
            // Key down
            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                keyDown.flags = flags
                keyDown.post(tap: .cghidEventTap)
            }
            
            // Key up
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                keyUp.flags = flags
                keyUp.post(tap: .cghidEventTap)
            }
            
            // Small delay between characters
            usleep(1000)  // 1ms
        }
    }
    
    // MARK: - Key Code Mapping (for character-by-character method)
    
    private let shiftCharacters: Set<Character> = [
        "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+",
        "{", "}", "|", ":", "\"", "<", ">", "?", "~"
    ]
    
    private func keyCodeForCharacter(_ char: Character) -> CGKeyCode? {
        let keyMap: [Character: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
            "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
            "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
            " ": 49, "`": 50,
            // Uppercase (same key codes)
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
            "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32,
            "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45, "M": 46,
        ]
        return keyMap[char]
    }
}
