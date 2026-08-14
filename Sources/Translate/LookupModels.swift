import Foundation

public struct Definition: Decodable, Equatable, Sendable {
    public let partOfSpeech: String
    /// Chỉ có với nghĩa chuyên ngành ("computing", "law") — đúng chỗ mà một
    /// bản dịch chung là kém tin cậy nhất.
    public let domain: String?
    public let gloss: String

    public init(partOfSpeech: String, domain: String?, gloss: String) {
        self.partOfSpeech = partOfSpeech
        self.domain = domain
        self.gloss = gloss
    }
}

public struct Lookup: Decodable, Equatable, Sendable {
    public let source: String
    public let sourceTruncated: Bool
    public let definitions: [Definition]
    public let translation: String?
    public let sourceLang: String?
    /// Ngôn ngữ THỰC SỰ được dịch sang — không nhất thiết là cái đã cấu hình.
    /// Khi quy tắc no-op thử lại vào ngôn ngữ dự phòng, hai cái khác nhau và
    /// nhãn phải bám theo cái này.
    public let targetLang: String
    public let definitionLang: String?

    public static let empty = Lookup(source: "", sourceTruncated: false, definitions: [],
                                     translation: nil, sourceLang: nil, targetLang: "vi",
                                     definitionLang: nil)

    public init(source: String, sourceTruncated: Bool, definitions: [Definition],
                translation: String?, sourceLang: String?, targetLang: String,
                definitionLang: String?) {
        self.source = source
        self.sourceTruncated = sourceTruncated
        self.definitions = definitions
        self.translation = translation
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.definitionLang = definitionLang
    }

    /// Các part of speech có mặt, đã khử trùng lặp — "noun · verb".
    public var partOfSpeechLine: String {
        var seen: [String] = []
        for d in definitions where !d.partOfSpeech.isEmpty && !seen.contains(d.partOfSpeech) {
            seen.append(d.partOfSpeech)
        }
        return seen.joined(separator: " · ")
    }
}

public struct LangConfig: Decodable, Equatable, Sendable {
    /// `nil` = auto-detect.
    public let source: String?
    public let target: String
    public let other: String

    public init(source: String?, target: String, other: String) {
        self.source = source
        self.target = target
        self.other = other
    }
}

public struct SavedWord: Decodable, Equatable, Sendable {
    public let word: String
    public let savedAt: Int
}

public struct HistoryEntry: Decodable, Equatable, Sendable {
    public let id: Int
    public let source: String
    public let translation: String?
    public let lookedUpAt: Int
}

extension JSONDecoder {
    /// Core serialize bằng snake_case; một decoder dùng chung để không chỗ nào
    /// quên đặt chiến lược này.
    public static let ktranslate: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
