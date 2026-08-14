import Foundation

/// React dùng `Intl.DisplayNames`; bản Swift tương đương là `Locale`.
public enum LanguageNames {
    public static let auto = "auto"

    public static func name(_ code: String) -> String {
        // Mã lạ rơi về chính nó: thà hiện "zzz" còn hơn một ô trống.
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}
