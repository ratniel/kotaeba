import AppKit
import Foundation

struct HotkeyShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: HotkeyModifiers

    static let `default` = HotkeyShortcut(
        keyCode: Constants.Hotkey.defaultKeyCode,
        modifiers: Constants.Hotkey.defaultModifiers
    )

    var displayString: String {
        "\(modifiers.displayString)\(CGKeyCode(keyCode).displayString ?? "Key \(keyCode)")"
    }

    var processorConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(
            keyCode: keyCode,
            requiredModifiers: modifiers,
            escapeKeyCode: Constants.Hotkey.escapeKeyCode,
            minimumHoldDuration: Constants.Hotkey.minimumHoldDuration,
            doubleTapLockWindow: Constants.Hotkey.doubleTapLockWindow
        )
    }
}

enum HotkeyShortcutStore {
    static func load(defaults: UserDefaults = .standard) -> HotkeyShortcut {
        guard let keyCodeValue = defaults.object(forKey: Constants.UserDefaultsKeys.hotkeyKeyCode) as? NSNumber,
              let modifiersValue = defaults.object(forKey: Constants.UserDefaultsKeys.hotkeyModifiers) as? NSNumber else {
            return .default
        }

        let rawKeyCode = keyCodeValue.int64Value
        let rawModifiers = modifiersValue.int64Value
        guard (0...Int64(UInt16.max)).contains(rawKeyCode),
              (0...Int64(UInt32.max)).contains(rawModifiers) else {
            return .default
        }

        let shortcut = HotkeyShortcut(
            keyCode: UInt16(rawKeyCode),
            modifiers: HotkeyModifiers(rawValue: UInt32(rawModifiers)).knownModifiers
        )

        switch HotkeyShortcutRules.validation(for: shortcut) {
        case .valid:
            return shortcut
        case .invalid:
            return .default
        }
    }

    static func save(_ shortcut: HotkeyShortcut, defaults: UserDefaults = .standard) {
        defaults.set(Int(shortcut.keyCode), forKey: Constants.UserDefaultsKeys.hotkeyKeyCode)
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: Constants.UserDefaultsKeys.hotkeyModifiers)
    }
}

enum HotkeyShortcutValidation: Equatable {
    case valid(caution: String?)
    case invalid(String)
}

enum HotkeyShortcutRules {
    static let avoidanceSuggestions: [HotkeyAvoidanceSuggestion] = [
        suggestion(keyCode: 8, modifiers: .command, reason: "Copy"),
        suggestion(keyCode: 9, modifiers: .command, reason: "Paste"),
        suggestion(keyCode: 7, modifiers: .command, reason: "Cut"),
        suggestion(keyCode: 0, modifiers: .command, reason: "Select All"),
        suggestion(keyCode: 6, modifiers: .command, reason: "Undo"),
        suggestion(keyCode: 1, modifiers: .command, reason: "Save"),
        suggestion(keyCode: 3, modifiers: .command, reason: "Find"),
        suggestion(keyCode: 13, modifiers: .command, reason: "Close Window"),
        suggestion(keyCode: 12, modifiers: .command, reason: "Quit App"),
        suggestion(keyCode: 49, modifiers: .command, reason: "Spotlight"),
    ]

    static var avoidanceHelpText: String {
        let shortcuts = avoidanceSuggestions.map(\.shortcut.displayString).joined(separator: ", ")
        return "Avoid common shortcuts such as \(shortcuts)."
    }

    static func validation(for shortcut: HotkeyShortcut) -> HotkeyShortcutValidation {
        guard shortcut.modifiers.containsTriggerModifier else {
            return .invalid("Use Control, Option, or Command with a key.")
        }

        guard shortcut.keyCode != Constants.Hotkey.escapeKeyCode else {
            return .invalid("Escape is reserved for cancelling a recording.")
        }

        guard CGKeyCode(shortcut.keyCode).displayString != nil else {
            return .invalid("That key is not supported yet.")
        }

        if let suggestion = avoidanceSuggestions.first(where: { $0.shortcut == shortcut }) {
            return .valid(caution: "\(shortcut.displayString) is commonly used for \(suggestion.reason). Consider a less generic shortcut.")
        }

        return .valid(caution: nil)
    }

    private static func suggestion(
        keyCode: UInt16,
        modifiers: HotkeyModifiers,
        reason: String
    ) -> HotkeyAvoidanceSuggestion {
        let shortcut = HotkeyShortcut(keyCode: keyCode, modifiers: modifiers)
        return HotkeyAvoidanceSuggestion(
            id: "\(shortcut.keyCode)-\(shortcut.modifiers.rawValue)",
            shortcut: shortcut,
            reason: reason
        )
    }
}

struct HotkeyAvoidanceSuggestion: Identifiable, Equatable {
    let id: String
    let shortcut: HotkeyShortcut
    let reason: String
}

extension HotkeyModifiers {
    private static let knownMask: UInt32 = control.rawValue | shift.rawValue | option.rawValue | command.rawValue

    var knownModifiers: HotkeyModifiers {
        HotkeyModifiers(rawValue: rawValue & Self.knownMask)
    }

    var containsTriggerModifier: Bool {
        contains(.control) || contains(.option) || contains(.command)
    }

    var displayString: String {
        var symbols = ""
        if contains(.control) {
            symbols += "⌃"
        }
        if contains(.option) {
            symbols += "⌥"
        }
        if contains(.shift) {
            symbols += "⇧"
        }
        if contains(.command) {
            symbols += "⌘"
        }
        return symbols
    }

    init(modifierFlags: NSEvent.ModifierFlags) {
        var modifiers: HotkeyModifiers = []
        if modifierFlags.contains(.control) {
            modifiers.insert(.control)
        }
        if modifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if modifierFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if modifierFlags.contains(.command) {
            modifiers.insert(.command)
        }
        self = modifiers
    }
}
