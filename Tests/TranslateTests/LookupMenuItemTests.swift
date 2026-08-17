import Carbon.HIToolbox
import XCTest
@testable import Translate

final class LookupMenuItemTests: XCTestCase {
    /// Giá trị kỳ vọng gõ TAY, không ghép từ `displayString`: ghép lại chính
    /// hàm đang được kiểm thì test đúng với mọi thứ tự ký hiệu, kể cả thứ tự
    /// sai — đúng cái bug mà nhãn `⌘⇧D` cũ mắc phải (macOS xếp `⇧⌘D`).
    func testTheTitleCarriesTheShortcutInMacOSGlyphOrder() {
        XCTAssertEqual(LookupMenuItem.title(for: .default), "Tra từ đang chọn  ⇧⌘D")
    }

    /// Vế thật sự quan trọng: nhãn phải ĐI THEO tổ hợp đang dùng. Một literal
    /// gõ tay vẫn qua được test ở trên (nó trùng giá trị mặc định) nhưng chết
    /// ở đây.
    func testTheTitleFollowsACustomCombo() {
        let combo = HotkeyCombo(
            keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey))
        XCTAssertEqual(LookupMenuItem.title(for: combo), "Tra từ đang chọn  ⌃⌥J")
    }
}
