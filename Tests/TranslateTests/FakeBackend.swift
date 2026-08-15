import Foundation
@testable import Translate

/// Double đồng bộ cho state machine. `lookup` gọi completion ngay lập tức để
/// test không cần expectation.
final class FakeBackend: TranslateBackend {
    var storedConfig: LangConfig?
    var lookupResult: Lookup = .empty
    private(set) var lookupCount = 0

    init(config: LangConfig?) { storedConfig = config }

    func capture() -> CaptureOutcome { .empty }
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void) {
        lookupCount += 1
        completion(lookupResult)
    }
    func languages() -> [String] { ["en", "vi", "de"] }
    func recentLanguages() -> [String] { ["vi"] }
    func langConfig() -> LangConfig? { storedConfig }
    /// Trả về khác với args ở `other` — mô phỏng backend thật sửa xung đột
    /// ngôn ngữ. Nếu echo lại nguyên args, một `self.config` dựng lạc quan
    /// tại chỗ từ cùng args sẽ trùng với `stored` và test không thể phân biệt
    /// hai cách viết.
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig? {
        storedConfig = LangConfig(source: source, target: target, other: other + "-repaired")
        return storedConfig
    }
    func hasAccessibility() -> Bool { true }
    func requestAccessibility() -> Bool { true }
    func ttsAvailable() -> Bool { true }
    func speak(_ text: String) {}
    func isSaved(_ word: String) -> Bool { false }
    @discardableResult func setSaved(_ word: String, saved: Bool) -> Bool { true }
}
