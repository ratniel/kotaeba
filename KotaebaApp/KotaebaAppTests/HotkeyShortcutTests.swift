import XCTest
@testable import KotaebaApp

final class HotkeyShortcutTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HotkeyShortcutTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLoadReturnsDefaultWhenNoShortcutIsStored() {
        XCTAssertEqual(HotkeyShortcutStore.load(defaults: defaults), .default)
    }

    func testSaveAndLoadRoundTrip() {
        let shortcut = HotkeyShortcut(keyCode: 49, modifiers: [.control, .option])

        HotkeyShortcutStore.save(shortcut, defaults: defaults)

        XCTAssertEqual(HotkeyShortcutStore.load(defaults: defaults), shortcut)
    }

    func testInvalidStoredShortcutFallsBackToDefault() {
        defaults.set(999, forKey: Constants.UserDefaultsKeys.hotkeyKeyCode)
        defaults.set(Int(HotkeyModifiers.control.rawValue), forKey: Constants.UserDefaultsKeys.hotkeyModifiers)

        XCTAssertEqual(HotkeyShortcutStore.load(defaults: defaults), .default)
    }

    func testOutOfRangeStoredShortcutFallsBackToDefault() {
        defaults.set(Int64(UInt16.max) + 1, forKey: Constants.UserDefaultsKeys.hotkeyKeyCode)
        defaults.set(Int(HotkeyModifiers.control.rawValue), forKey: Constants.UserDefaultsKeys.hotkeyModifiers)

        XCTAssertEqual(HotkeyShortcutStore.load(defaults: defaults), .default)

        defaults.set(7, forKey: Constants.UserDefaultsKeys.hotkeyKeyCode)
        defaults.set(-1, forKey: Constants.UserDefaultsKeys.hotkeyModifiers)

        XCTAssertEqual(HotkeyShortcutStore.load(defaults: defaults), .default)
    }

    func testValidationRejectsMissingTriggerModifier() {
        let noModifier = HotkeyShortcut(keyCode: 7, modifiers: [])
        let shiftOnly = HotkeyShortcut(keyCode: 7, modifiers: .shift)

        XCTAssertEqual(
            HotkeyShortcutRules.validation(for: noModifier),
            .invalid("Use Control, Option, or Command with a key.")
        )
        XCTAssertEqual(
            HotkeyShortcutRules.validation(for: shiftOnly),
            .invalid("Use Control, Option, or Command with a key.")
        )
    }

    func testValidationRejectsEscapeAndUnknownKeys() {
        XCTAssertEqual(
            HotkeyShortcutRules.validation(for: HotkeyShortcut(keyCode: 53, modifiers: .control)),
            .invalid("Escape is reserved for cancelling a recording.")
        )
        XCTAssertEqual(
            HotkeyShortcutRules.validation(for: HotkeyShortcut(keyCode: 999, modifiers: .control)),
            .invalid("That key is not supported yet.")
        )
    }

    func testValidationWarnsButAllowsCommonShortcuts() {
        let validation = HotkeyShortcutRules.validation(for: HotkeyShortcut(keyCode: 8, modifiers: .command))

        switch validation {
        case .valid(let caution):
            XCTAssertEqual(caution, "⌘C is commonly used for Copy. Consider a less generic shortcut.")
        case .invalid(let message):
            XCTFail("Expected warning-only validation, got invalid: \(message)")
        }
    }

    func testDisplayStringIncludesModifierSymbolsAndKey() {
        let shortcut = HotkeyShortcut(keyCode: 49, modifiers: [.control, .option, .shift])

        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧Space")
    }
}
