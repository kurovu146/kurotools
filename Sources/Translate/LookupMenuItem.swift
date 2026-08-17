import Foundation

/// Nhãn của mục "Tra từ đang chọn" trong menu bar.
///
/// Tách thành hàm thuần vì nhãn đó có HAI nguồn sự thật dễ trôi khỏi nhau: tổ
/// hợp phím đang thật sự sống (`TranslateController.currentHotkey`) và một
/// literal gõ tay trong `AppDelegate`. Bản trước gõ tay `⌘⇧D` — vừa đóng băng
/// ở tổ hợp mặc định (đổi phím tắt trong Settings xong, menu vẫn quảng cáo tổ
/// hợp cũ), vừa xếp ký hiệu SAI thứ tự macOS mà `HotkeyCombo.displayString`
/// dùng (`⇧⌘D`), nên hai chỗ mâu thuẫn nhau ngay ở giá trị mặc định.
public enum LookupMenuItem {
    public static func title(for combo: HotkeyCombo) -> String {
        "Tra từ đang chọn  \(combo.displayString)"
    }
}
