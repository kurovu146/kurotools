import Foundation

@_silgen_name("kt_init") private func kt_init(_ path: UnsafePointer<CChar>?) -> Bool
@_silgen_name("kt_string_free") private func kt_string_free(_ p: UnsafeMutablePointer<CChar>?)
@_silgen_name("kt_capture") private func kt_capture() -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_lookup") private func kt_lookup(_ t: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_languages") private func kt_languages() -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_lang_config") private func kt_lang_config() -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_set_lang_config") private func kt_set_lang_config(
    _ s: UnsafePointer<CChar>?, _ t: UnsafePointer<CChar>?, _ o: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_recent_languages") private func kt_recent_languages() -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_save_word") private func kt_save_word(_ w: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_unsave_word") private func kt_unsave_word(_ w: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_is_saved") private func kt_is_saved(_ w: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("kt_check_accessibility") private func kt_check_accessibility() -> Bool
@_silgen_name("kt_request_accessibility") private func kt_request_accessibility() -> Bool
@_silgen_name("kt_tts_available") private func kt_tts_available() -> Bool
@_silgen_name("kt_speak") private func kt_speak(_ t: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

public enum CaptureOutcome: Equatable, Sendable {
    case text(String)
    case empty
    case needsPermission
}

public protocol TranslateBackend: AnyObject {
    func capture() -> CaptureOutcome
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void)
    func languages() -> [String]
    func recentLanguages() -> [String]
    func langConfig() -> LangConfig?
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig?
    func hasAccessibility() -> Bool
    func requestAccessibility() -> Bool
    func ttsAvailable() -> Bool
    func speak(_ text: String)
    func isSaved(_ word: String) -> Bool
    /// Bản async của `isSaved` — để UI hỏi trạng thái lưu mà không chặn main
    /// thread chờ nó. Có default bên dưới nên backend đồng bộ không cần tự
    /// triển khai lại; test double nào cần dựng thứ tự trả lời đảo ngược
    /// (xem `DeferredBackend` trong `SourceActionsTests`) thì tự override.
    func isSavedAsync(_ word: String, completion: @escaping (Bool) -> Void)
    @discardableResult func setSaved(_ word: String, saved: Bool) -> Bool
}

extension TranslateBackend {
    /// Mặc định: chạy `isSaved` đồng bộ trên background queue rồi trả kết quả
    /// về main thread. `KTranslateBridge.isSaved` gọi HTTP nên không thể chạy
    /// thẳng trên main thread mà không treo UI đang hiện popup — cùng lý do
    /// `lookup` ở trên có `queue` riêng của nó. Nhờ default này,
    /// `KTranslateBridge` không cần sửa gì để có bản async không chặn.
    public func isSavedAsync(_ word: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let value = self.isSaved(word)
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }
}

/// Lớp DUY NHẤT được phép chạm vào con trỏ C. Mọi hàm copy chuỗi sang Swift rồi
/// giải phóng ngay — con trỏ không bao giờ sống quá một lời gọi.
public final class KTranslateBridge: TranslateBackend, @unchecked Sendable {
    public static let shared = KTranslateBridge()

    /// Lookup gọi HTTP đồng bộ. Queue riêng để main thread — nơi popup đang
    /// hiện — không bao giờ bị chặn.
    private let queue = DispatchQueue(label: "com.kurovu.kurotools.translate", qos: .userInitiated)

    private init() {}

    private func takeString(_ ptr: UnsafeMutablePointer<CChar>?) -> String? {
        guard let ptr else { return nil }
        defer { kt_string_free(ptr) }
        return String(cString: ptr)
    }

    private func takeJSON<T: Decodable>(_ ptr: UnsafeMutablePointer<CChar>?, as type: T.Type) -> T? {
        guard let text = takeString(ptr), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder.ktranslate.decode(type, from: data)
    }

    @discardableResult
    public func start(dbPath: URL) -> Bool { dbPath.path.withCString { kt_init($0) } }

    private struct CaptureResult: Decodable { let ok: Bool; let text: String }
    private struct OkFlag: Decodable { let ok: Bool }
    private struct SavedFlag: Decodable { let saved: Bool }

    /// **Phải gọi TRƯỚC khi show popup** — show trước sẽ cướp focus và mọi lần
    /// capture trả về rỗng.
    ///
    /// Phân biệt "không có gì được chọn" với "thiếu quyền": chỉ trường hợp sau
    /// mới đáng làm phiền người dùng.
    public func capture() -> CaptureOutcome {
        guard let r = takeJSON(kt_capture(), as: CaptureResult.self), r.ok, !r.text.isEmpty else {
            return hasAccessibility() ? .empty : .needsPermission
        }
        return .text(r.text)
    }

    public func lookup(_ text: String, completion: @escaping (Lookup) -> Void) {
        queue.async {
            let result = text.withCString { self.takeJSON(kt_lookup($0), as: Lookup.self) }
            let lookup = result ?? Lookup.empty
            DispatchQueue.main.async { completion(lookup) }
        }
    }

    public func languages() -> [String] { takeJSON(kt_languages(), as: [String].self) ?? [] }
    public func recentLanguages() -> [String] { takeJSON(kt_recent_languages(), as: [String].self) ?? [] }
    public func langConfig() -> LangConfig? { takeJSON(kt_lang_config(), as: LangConfig.self) }

    /// Trả về thứ backend THỰC SỰ lưu — nó sửa xung đột ngôn ngữ, nên một cập
    /// nhật lạc quan phía UI có thể bất đồng với nó. `nil` = lưu thất bại.
    public func setLangConfig(source: String?, target: String, other: String) -> LangConfig? {
        (source ?? "auto").withCString { s in
            target.withCString { t in
                other.withCString { o in
                    takeJSON(kt_set_lang_config(s, t, o), as: LangConfig.self)
                }
            }
        }
    }

    public func hasAccessibility() -> Bool { kt_check_accessibility() }
    public func requestAccessibility() -> Bool { kt_request_accessibility() }
    public func ttsAvailable() -> Bool { kt_tts_available() }

    public func speak(_ text: String) {
        queue.async { _ = text.withCString { self.takeString(kt_speak($0)) } }
    }

    public func isSaved(_ word: String) -> Bool {
        word.withCString { takeJSON(kt_is_saved($0), as: SavedFlag.self)?.saved ?? false }
    }

    @discardableResult
    public func setSaved(_ word: String, saved: Bool) -> Bool {
        word.withCString { ptr in
            takeJSON(saved ? kt_save_word(ptr) : kt_unsave_word(ptr), as: OkFlag.self)?.ok ?? false
        }
    }
}
