import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Settings
@testable import Translate

final class HotkeyRecorderTests: XCTestCase {
    func testCocoaModifiersBecomeCarbonModifiers() {
        let combo = HotkeyRecorder.combo(
            fromCarbonKeyCode: UInt32(kVK_ANSI_K), cocoaModifiers: [.command, .shift])
        XCTAssertEqual(combo, HotkeyCombo(keyCode: UInt32(kVK_ANSI_K),
                                          modifiers: UInt32(cmdKey | shiftKey)))
    }

    func testAllFourModifiersMap() {
        let combo = HotkeyRecorder.combo(
            fromCarbonKeyCode: UInt32(kVK_ANSI_J),
            cocoaModifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(combo?.modifiers, UInt32(cmdKey | shiftKey | optionKey | controlKey))
    }

    func testAKeyWithoutModifiersIsRefused() {
        XCTAssertNil(HotkeyRecorder.combo(fromCarbonKeyCode: UInt32(kVK_ANSI_K), cocoaModifiers: []))
    }

    func testCapsLockAloneDoesNotCountAsAModifier() {
        // Caps Lock trên máy này đã bị ánh xạ thành Ctrl ở tầng hidutil, nhưng
        // cờ .capsLock vẫn tới được app — nó không phải modifier hợp lệ.
        XCTAssertNil(HotkeyRecorder.combo(
            fromCarbonKeyCode: UInt32(kVK_ANSI_K), cocoaModifiers: [.capsLock]))
    }
}

/// `RecorderField.keyDown(with:)` không cần cửa sổ thật để chạy — event
/// được dựng tay qua `NSEvent.keyEvent`, không đi qua responder chain.
/// `startRecording()` cũng test được mà không cần cửa sổ: `window` là `nil`
/// trong test nên `window?.makeFirstResponder(self)` là optional chaining
/// im lặng bỏ qua, còn phần còn lại (gán `isRecording`, đổi `title`) chạy
/// bình thường. Điều KHÔNG kiểm được ở đây: nhánh `makeFirstResponder` thật
/// sự chạy (cần `window` khác `nil`), và việc AppKit thật sự định tuyến phím
/// tới nút này khi nó là first responder — cả hai cần một `NSWindow` sống
/// trong một app đang chạy.
final class RecorderFieldTests: XCTestCase {
    private func syntheticKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode)!
    }

    func testEscapeCancelsRecordingWithoutProducingACombo() {
        let field = RecorderField()
        var recorded: HotkeyCombo?
        field.onRecorded = { recorded = $0 }
        field.isRecording = true

        field.keyDown(with: syntheticKeyDown(keyCode: UInt16(kVK_Escape), modifiers: []))

        XCTAssertFalse(field.isRecording)
        XCTAssertNil(recorded)
    }

    func testKeyWithoutModifiersKeepsWaiting() {
        let field = RecorderField()
        var recorded: HotkeyCombo?
        field.onRecorded = { recorded = $0 }
        field.isRecording = true

        field.keyDown(with: syntheticKeyDown(keyCode: UInt16(kVK_ANSI_K), modifiers: []))

        XCTAssertTrue(field.isRecording,
                      "thiếu modifier phải tiếp tục chờ, không đóng ô ghi")
        XCTAssertNil(recorded)
    }

    func testCapsLockAloneKeepsWaiting() {
        let field = RecorderField()
        var recorded: HotkeyCombo?
        field.onRecorded = { recorded = $0 }
        field.isRecording = true

        field.keyDown(with: syntheticKeyDown(keyCode: UInt16(kVK_ANSI_K), modifiers: .capsLock))

        XCTAssertTrue(field.isRecording)
        XCTAssertNil(recorded)
    }

    func testClickingTheButtonStartsRecordingAndShowsThePrompt() {
        let field = RecorderField()
        XCTAssertNil(field.window)   // đường target-action không cần cửa sổ để chạy

        _ = field.target?.perform(field.action, with: field)

        XCTAssertTrue(field.isRecording)
        XCTAssertEqual(field.title, "Bấm tổ hợp phím…")
    }

    func testValidComboEndsRecordingAndReportsIt() {
        let field = RecorderField()
        var recorded: HotkeyCombo?
        field.onRecorded = { recorded = $0 }
        field.isRecording = true

        field.keyDown(with: syntheticKeyDown(
            keyCode: UInt16(kVK_ANSI_J), modifiers: [.command, .shift]))

        XCTAssertFalse(field.isRecording)
        XCTAssertEqual(recorded, HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey)))
        XCTAssertEqual(field.combo, recorded)
    }
}
