import XCTest
@testable import Translate

final class LookupModelsTests: XCTestCase {
    // Fixture lấy từ output thật của kt_lookup, không phải JSON tự bịa.
    func testDecodesTheCoreLookupShape() throws {
        let json = """
        {"source":"ephemeral","source_truncated":false,
         "definitions":[{"part_of_speech":"adjective","domain":null,"gloss":"lasting a very short time"}],
         "translation":"phù du","source_lang":"en","target_lang":"vi","definition_lang":"en"}
        """.data(using: .utf8)!
        let lookup = try JSONDecoder.ktranslate.decode(Lookup.self, from: json)
        XCTAssertEqual(lookup.source, "ephemeral")
        XCTAssertFalse(lookup.sourceTruncated)
        XCTAssertEqual(lookup.translation, "phù du")
        XCTAssertEqual(lookup.targetLang, "vi")
        XCTAssertEqual(lookup.definitions.first?.partOfSpeech, "adjective")
        XCTAssertNil(lookup.definitions.first?.domain)
    }

    func testDecodesTheUnavailableState() throws {
        // translation: null + definitions rỗng là trạng thái UI phải render,
        // KHÔNG BAO GIỜ là dialog lỗi.
        let json = """
        {"source":"xyz","source_truncated":false,"definitions":[],
         "translation":null,"source_lang":null,"target_lang":"vi","definition_lang":null}
        """.data(using: .utf8)!
        let lookup = try JSONDecoder.ktranslate.decode(Lookup.self, from: json)
        XCTAssertNil(lookup.translation)
        XCTAssertTrue(lookup.definitions.isEmpty)
        XCTAssertNil(lookup.sourceLang)
    }

    func testPartOfSpeechLineDeduplicates() {
        // Endpoint lặp part of speech trên mọi sense trong một nhóm, nên nối
        // thô sẽ ra "noun · noun · verb".
        let defs = [
            Definition(partOfSpeech: "noun", domain: nil, gloss: "a"),
            Definition(partOfSpeech: "noun", domain: nil, gloss: "b"),
            Definition(partOfSpeech: "verb", domain: nil, gloss: "c"),
        ]
        let lookup = Lookup(source: "x", sourceTruncated: false, definitions: defs,
                            translation: nil, sourceLang: "en", targetLang: "vi",
                            definitionLang: "en")
        XCTAssertEqual(lookup.partOfSpeechLine, "noun · verb")
    }

    func testDecodesLangConfigWithNullSource() throws {
        let json = #"{"source":null,"target":"vi","other":"en"}"#.data(using: .utf8)!
        let config = try JSONDecoder.ktranslate.decode(LangConfig.self, from: json)
        XCTAssertNil(config.source)
        XCTAssertEqual(config.target, "vi")
    }

    func testLanguageNamesAreHumanReadable() {
        XCTAssertEqual(LanguageNames.name("vi"), "Vietnamese")
        XCTAssertEqual(LanguageNames.name("de"), "German")
        // Mã lạ rơi về chính nó — thà hiện "zzz" còn hơn một ô trống.
        XCTAssertEqual(LanguageNames.name("zzz"), "zzz")
    }

    func testLanguageNamesResolveLegacyAndCLDRGapCodesWithoutAHardcodedTable() {
        // `iw` là mã ISO cũ Google vẫn dùng cho Hebrew; `bho` (Bhojpuri) là
        // một mã CLDR "hiếm". Bản TS cũ (~/dev/ktranslate/src/lang.ts) cần
        // bảng DISPLAY_ALIASES + FALLBACK_NAMES tay cho các mã này vì
        // Intl.DisplayNames của trình duyệt không phủ hết. Đã ĐO trên máy
        // này (task-8-report.md, phần "Đo LanguageNames"): Locale/CLDR của
        // macOS đã phủ đủ toàn bộ 10 mã trong hai bảng đó — không mã nào
        // rơi về chính nó — nên KHÔNG cần port hai bảng sang Swift.
        XCTAssertEqual(LanguageNames.name("iw"), "Hebrew")
        XCTAssertEqual(LanguageNames.name("bho"), "Bhojpuri")
    }

    func testLanguageNamesDisambiguateRegionQualifiedCodes() {
        // Gap thật duy nhất đo được: `zh-CN` và `zh-TW` khác `target_lang`
        // Rust trả về, nhưng `localizedString(forLanguageCode:)` bỏ mất
        // phần vùng miền nên cả hai cùng ra "Chinese" — hai lựa chọn khác
        // nhau trong picker hiện y hệt nhau, người dùng không phân biệt được.
        XCTAssertNotEqual(LanguageNames.name("zh-CN"), LanguageNames.name("zh-TW"))
    }
}
