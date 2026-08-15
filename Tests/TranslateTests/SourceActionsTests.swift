import XCTest
@testable import Translate

/// Backend trả lời `isSaved` theo lệnh, để test dựng lại đúng thứ tự đảo ngược.
final class DeferredBackend: TranslateBackend {
    private var pending: [(String, (Bool) -> Void)] = []
    var writeSucceeds = true

    func answer(word: String, saved: Bool) {
        pending.removeAll { entry in
            guard entry.0 == word else { return false }
            entry.1(saved)
            return true
        }
    }
    func isSavedAsync(_ word: String, completion: @escaping (Bool) -> Void) {
        pending.append((word, completion))
    }

    func capture() -> CaptureOutcome { .empty }
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void) { completion(.empty) }
    func languages() -> [String] { [] }
    func recentLanguages() -> [String] { [] }
    func langConfig() -> LangConfig? { nil }
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig? { nil }
    func hasAccessibility() -> Bool { true }
    func requestAccessibility() -> Bool { true }
    func ttsAvailable() -> Bool { true }
    func speak(_ text: String) {}
    func isSaved(_ word: String) -> Bool { false }
    @discardableResult func setSaved(_ word: String, saved: Bool) -> Bool { writeSucceeds }
}

@MainActor
final class SourceActionsTests: XCTestCase {
    func testStaleIsSavedAnswerCannotOverwriteTheNewerWord() {
        let backend = DeferredBackend()
        let m = SourceActionsModel(backend: backend)
        m.load(text: "first")
        m.load(text: "second")
        // Câu trả lời của từ CŨ về sau câu trả lời của từ MỚI.
        backend.answer(word: "second", saved: false)
        backend.answer(word: "first", saved: true)
        XCTAssertFalse(m.saved, "the older answer must not overwrite the newer one")
    }

    func testFailedWriteRollsTheButtonBack() {
        let backend = DeferredBackend()
        backend.writeSucceeds = false
        let m = SourceActionsModel(backend: backend)
        m.toggleSave(text: "word")
        XCTAssertFalse(m.saved, "a write that did not happen must not look like it did")
    }

    func testSuccessfulWriteKeepsTheOptimisticState() {
        let backend = DeferredBackend()
        let m = SourceActionsModel(backend: backend)
        m.toggleSave(text: "word")
        XCTAssertTrue(m.saved)
    }
}
