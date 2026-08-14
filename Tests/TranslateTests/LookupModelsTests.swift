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
}
