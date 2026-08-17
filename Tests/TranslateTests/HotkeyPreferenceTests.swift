import XCTest
import Carbon.HIToolbox
@testable import Translate

final class HotkeyPreferenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "kurotools.hotkey.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
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
}
