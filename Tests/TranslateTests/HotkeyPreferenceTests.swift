import XCTest
import TestSupport
import Carbon.HIToolbox
@testable import Translate

final class HotkeyPreferenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        (defaults, suiteName) = PreferencesSandbox.make("hotkey")
    }

    override func tearDown() {
        PreferencesSandbox.destroy(suiteName)
    }

    func testTheDefaultIsCommandShiftD() {
        let combo = HotkeyPreference.load(defaults: defaults)
        XCTAssertEqual(combo.keyCode, UInt32(kVK_ANSI_D))
        XCTAssertEqual(combo.modifiers, UInt32(cmdKey | shiftKey))
        // ⇧⌘D, không phải ⌘⇧D — cùng thứ tự ⌃⌥⇧⌘ mà
        // testDisplayStringOrdersModifiersLikeMacOS xác nhận bên dưới (Command
        // luôn đứng cuối, khớp macOS thật: Finder hiện "⇧⌘N" cho Shift-Command-N).
        XCTAssertEqual(combo.displayString, "⇧⌘D")
    }

    func testASavedComboRoundTrips() {
        let combo = HotkeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey))
        HotkeyPreference.save(combo, defaults: defaults)
        XCTAssertEqual(HotkeyPreference.load(defaults: defaults), combo)
    }

    func testDisplayStringOrdersModifiersLikeMacOS() {
        // Thứ tự macOS: ⌃⌥⇧⌘
        let combo = HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘K")
    }

    func testAComboWithoutAModifierIsInvalid() {
        // Một phím trần làm hotkey toàn cục sẽ nuốt phím đó ở MỌI app.
        XCTAssertFalse(HotkeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: 0).isValid)
        XCTAssertTrue(HotkeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey)).isValid)
    }

    func testAnInvalidStoredComboFallsBackToTheDefault() {
        defaults.set(0, forKey: "hotkeyModifiers")
        defaults.set(Int(kVK_ANSI_D), forKey: "hotkeyKeyCode")
        XCTAssertEqual(HotkeyPreference.load(defaults: defaults), HotkeyCombo.default)
    }

    // MARK: - Fix round 1

    /// `UInt32(defaults.integer(forKey:))` traps on a negative stored Int —
    /// a hand-edited or corrupted preference plist must fall back to
    /// `.default` instead of crashing `TranslateController.start(dbPath:)`
    /// at launch, before `isValid` ever gets a chance to run.
    func testANegativeStoredKeyCodeFallsBackToTheDefaultInsteadOfCrashing() {
        defaults.set(-1, forKey: "hotkeyKeyCode")
        defaults.set(Int(cmdKey), forKey: "hotkeyModifiers")
        XCTAssertEqual(HotkeyPreference.load(defaults: defaults), HotkeyCombo.default)
    }

    func testANegativeStoredModifiersValueFallsBackToTheDefaultInsteadOfCrashing() {
        defaults.set(Int(kVK_ANSI_D), forKey: "hotkeyKeyCode")
        defaults.set(-1, forKey: "hotkeyModifiers")
        XCTAssertEqual(HotkeyPreference.load(defaults: defaults), HotkeyCombo.default)
    }

    /// macOS virtual key codes are 0...127 — a stored value outside that
    /// range corresponds to no physical key, so it would register a hotkey
    /// that can never fire while the UI still reports it as active.
    func testAnOutOfRangeStoredKeyCodeFallsBackToTheDefault() {
        defaults.set(200, forKey: "hotkeyKeyCode")
        defaults.set(Int(cmdKey), forKey: "hotkeyModifiers")
        XCTAssertEqual(HotkeyPreference.load(defaults: defaults), HotkeyCombo.default)
    }

    /// `1 << 20` is the raw value of Cocoa's `NSEvent.ModifierFlags.command`
    /// — a different bit than Carbon's `cmdKey` that `isValid`/`displayString`
    /// actually understand. `isValid` must check membership in the four
    /// Carbon masks, not merely `!= 0`, or this (and stray bits like
    /// `alphaLock`) would pass as a valid combo with no visible modifier.
    func testCocoaCommandBitIsRejectedNotCarbonCommandBit() {
        XCTAssertFalse(HotkeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: 1 << 20).isValid)
    }
}
