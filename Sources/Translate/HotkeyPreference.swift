import Carbon.HIToolbox
import Foundation

/// Một tổ hợp phím Carbon, đủ để `RegisterEventHotKey` dùng lại.
public struct HotkeyCombo: Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let `default` = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))

    /// Hotkey toàn cục không có modifier Carbon nào sẽ nuốt phím đó ở MỌI
    /// app — không phải một lựa chọn người dùng nên được phép mắc. Kiểm
    /// THÀNH VIÊN của bốn mask Carbon, không phải `!= 0`: một bit lạ (vd
    /// `alphaLock`, hay bit Command của Cocoa `NSEvent.ModifierFlags` — khác
    /// hẳn mask Carbon) có thể khác 0 mà `displayString` không hiện glyph
    /// nào cho nó, sinh ra một hotkey trông như bấm nguyên phím trần.
    public var isValid: Bool {
        modifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey) != 0
    }

    /// Thứ tự ký hiệu theo quy ước macOS: ⌃⌥⇧⌘.
    public var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Escape): "⎋",
        ]
        return names[code] ?? "key \(code)"
    }
}

public enum HotkeyPreference {
    static let keyCodeKey = "hotkeyKeyCode"
    static let modifiersKey = "hotkeyModifiers"

    /// macOS virtual key codes hợp lệ nằm trong 0...127 (`Carbon.HIToolbox`'s
    /// `kVK_*`). Một giá trị ngoài dải đó không ứng với phím vật lý nào —
    /// `RegisterEventHotKey` vẫn "đăng ký thành công" nó nhưng nó không bao
    /// giờ bắn: một hotkey chết mà UI vẫn hiển thị như đang hoạt động.
    private static let validKeyCodeRange = 0...127

    public static func load(defaults: UserDefaults = .standard) -> HotkeyCombo {
        guard defaults.object(forKey: keyCodeKey) != nil else { return .default }
        // Đọc `Int` trước, kiểm miền RỒI MỚI ép sang `UInt32` — một plist
        // chỉnh tay hay ghi hỏng có thể chứa số âm, và `UInt32(negativeInt)`
        // là fatal error, không phải nil. Ép kiểu trước khi kiểm miền sẽ làm
        // sập app ngay lúc khởi động (`load()` chạy trong
        // `TranslateController.start`), trước khi `isValid` có cơ hội chạy.
        let storedKeyCode = defaults.integer(forKey: keyCodeKey)
        let storedModifiers = defaults.integer(forKey: modifiersKey)
        guard validKeyCodeRange.contains(storedKeyCode),
            (0...Int(UInt32.max)).contains(storedModifiers)
        else { return .default }

        let combo = HotkeyCombo(
            keyCode: UInt32(storedKeyCode), modifiers: UInt32(storedModifiers))
        // Giá trị đã lưu vẫn phải qua cùng cổng hợp lệ như giá trị vừa gõ:
        // một preference hỏng không được biến thành hotkey nuốt phím.
        return combo.isValid ? combo : .default
    }

    public static func save(_ combo: HotkeyCombo, defaults: UserDefaults = .standard) {
        defaults.set(Int(combo.keyCode), forKey: keyCodeKey)
        defaults.set(Int(combo.modifiers), forKey: modifiersKey)
    }
}
