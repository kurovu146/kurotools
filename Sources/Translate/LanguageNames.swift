import Foundation

/// React dùng `Intl.DisplayNames`; bản Swift tương đương là `Locale`.
public enum LanguageNames {
    public static let auto = "auto"

    public static func name(_ code: String) -> String {
        // `forIdentifier`, không phải `forLanguageCode`: cái sau bỏ mất phần
        // vùng miền, nên "zh-CN" và "zh-TW" — hai giá trị `target_lang` khác
        // nhau — cùng ra "Chinese" và không thể phân biệt trong picker. Đã đo
        // trên 133 mã của `lang::SUPPORTED` (task-8-report.md): so với bảng
        // DISPLAY_ALIASES/FALLBACK_NAMES tay của bản TS cũ, Locale/CLDR của
        // macOS đã tự phủ đủ — không mã nào rơi về chính nó — nên không cần
        // port hai bảng đó sang đây. Mã lạ rơi về chính nó: thà hiện "zzz"
        // còn hơn một ô trống.
        Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
    }
}
