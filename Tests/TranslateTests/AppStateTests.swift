import XCTest
@testable import Translate

/// Backend hoãn trả lời `lookup` theo lệnh, để test dựng lại đúng cảnh
/// completion CŨ tới SAU completion MỚI (I-6, final review) — cùng khuôn
/// `DeferredBackend` (SourceActionsTests.swift), nhưng hoãn ở `lookup` thay
/// vì `isSavedAsync`.
private final class DeferredLookupBackend: TranslateBackend {
    private var pending: [(Lookup) -> Void] = []
    var storedConfig: LangConfig?

    init(config: LangConfig?) { storedConfig = config }

    /// Trả lời request thứ `index` — 0 là request được `lookup` GỌI sớm
    /// nhất, không nhất thiết là request được TRẢ LỜI sớm nhất ở đây.
    func answer(at index: Int, targetLang: String) {
        pending[index](Lookup(source: "hallo", sourceTruncated: false, definitions: [],
                               translation: nil, sourceLang: nil, targetLang: targetLang,
                               definitionLang: nil))
    }

    func capture() -> CaptureOutcome { .empty }
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void) {
        pending.append(completion)
    }
    func languages() -> [String] { [] }
    func recentLanguages() -> [String] { [] }
    func langConfig() -> LangConfig? { storedConfig }
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig? {
        storedConfig = LangConfig(source: source, target: target, other: other)
        return storedConfig
    }
    func hasAccessibility() -> Bool { true }
    func requestAccessibility() -> Bool { true }
    func ttsAvailable() -> Bool { true }
    func speak(_ text: String) {}
    func isSaved(_ word: String) -> Bool { false }
    @discardableResult func setSaved(_ word: String, saved: Bool) -> Bool { true }
}

@MainActor
final class AppStateTests: XCTestCase {
    private func model(config: LangConfig?) -> AppModel {
        AppModel(backend: FakeBackend(config: config))
    }
    private let vi = LangConfig(source: nil, target: "vi", other: "en")

    func testPickerStaysClosedWhenConfigNeverLoaded() {
        let m = model(config: nil)
        m.picking = .source
        // config nil ⇒ không có picker để mở, dù đã yêu cầu.
        XCTAssertFalse(m.pickerOpen)
    }

    func testEscapeClosesThePickerFirstThenFallsThrough() {
        let m = model(config: vi)
        m.loadConfig()
        m.picking = .target
        XCTAssertTrue(m.escape(), "first Escape should consume the key closing the picker")
        XCTAssertNil(m.picking)
        XCTAssertFalse(m.escape(), "second Escape must fall through to dismiss the popup")
    }

    func testEscapeIsNotSwallowedByAnInvisiblePicker() {
        let m = model(config: nil)   // config chưa bao giờ tới
        m.picking = .source          // đã yêu cầu nhưng không hiện được
        XCTAssertFalse(m.escape(), "a press must not be eaten closing something invisible")
    }

    func testANewCaptureClearsAPendingPicker() {
        let m = model(config: vi)
        m.loadConfig()
        m.picking = .source
        m.handle(.text("hello"))
        XCTAssertNil(m.picking, "a stale picker would reopen over the new result")
    }

    func testACaptureThatFindsNothingSelectedClearsAPendingPickerAndGoesIdle() {
        let m = model(config: vi)
        m.loadConfig()
        m.picking = .source
        m.query = "leftover query"
        m.run("hello")   // move state away from .idle first, or the reset below proves nothing
        m.handle(.empty)
        XCTAssertNil(m.picking, "a stale picker would reopen over the idle screen")
        XCTAssertEqual(m.state, .idle)
        XCTAssertEqual(m.query, "")
    }

    func testBlankTextGoesIdleNotLoading() {
        let m = model(config: nil)
        m.run("hello")
        // Must actually leave .idle first — .idle is also the initializer's
        // default, so asserting the guard's *effect* requires starting
        // somewhere else.
        XCTAssertNotEqual(m.state, .idle)
        m.run("   ")
        XCTAssertEqual(m.state, .idle)
    }

    func testNeedsPermissionOutcomeSurfacesTheGate() {
        let m = model(config: nil)
        m.handle(.needsPermission)
        XCTAssertEqual(m.state, .needsPermission)
    }

    func testNeedsPermissionOutcomeClearsAPendingPickerToo() {
        let m = model(config: vi)
        m.loadConfig()
        m.picking = .target
        m.handle(.needsPermission)
        XCTAssertNil(m.picking, "a stale picker would reopen over the permission gate")
    }

    func testChangingLanguageReRunsTheSameTextWithoutRecapturing() {
        let backend = FakeBackend(config: vi)
        let m = AppModel(backend: backend)
        m.loadConfig()
        m.handle(.text("hallo"))
        let before = backend.lookupCount
        m.pick(.target, code: "en")
        XCTAssertEqual(backend.lookupCount, before + 1, "should re-run the text already in hand")
        XCTAssertEqual(backend.storedConfig?.target, "en")
    }

    func testDismissedResetsANeedsPermissionScreenToIdle() {
        let m = model(config: nil)
        m.handle(.needsPermission)
        m.dismissed()
        XCTAssertEqual(m.state, .idle, "leaves the timer-owning gate so PermissionGateView.onDisappear can stop polling")
    }

    func testDismissedLeavesOtherStatesAlone() {
        // FakeBackend.lookup gọi completion ĐỒNG BỘ, nên `run` đã ở `.done`
        // ngay khi trả về — không có cách quan sát `.loading` ở test này.
        let m = model(config: nil)
        m.run("hello")
        guard case .done = m.state else { return XCTFail("expected .done after a synchronous fake lookup") }
        m.dismissed()
        guard case .done = m.state else {
            return XCTFail("only the permission gate has a live resource to release")
        }
    }

    func testAStaleLookupCompletionCannotOverwriteANewerLanguagePick() {
        // I-6 (final review): chọn nhanh hai ngôn ngữ liên tiếp qua picker
        // chạy `run(lastText)` hai lần — nếu completion của lần CHẠY TRƯỚC
        // tới SAU completion của lần CHẠY SAU, nó ghi đè kết quả đúng bằng
        // một kết quả đã lỗi thời, và không còn request nào đang chờ để sửa
        // lại nhãn.
        let backend = DeferredLookupBackend(config: vi)
        let m = AppModel(backend: backend)
        m.loadConfig()
        m.handle(.text("hallo"))     // pending[0] — không trả lời, không liên quan
        m.pick(.target, code: "en")  // pending[1]
        m.pick(.target, code: "de")  // pending[2] — thay thế pending[1]

        // Đảo ngược thứ tự tới: request MỚI HƠN ("de") trả lời TRƯỚC, request
        // CŨ HƠN ("en") trả lời SAU.
        backend.answer(at: 2, targetLang: "de")
        backend.answer(at: 1, targetLang: "en")

        guard case .done(let result) = m.state else { return XCTFail("expected .done") }
        XCTAssertEqual(result.targetLang, "de",
            "the stale 'en' answer arriving after 'de' must not overwrite the newer pick")
    }

    func testPickRendersWhatTheBackendActuallyStoredNotAnOptimisticGuess() {
        // FakeBackend deliberately returns `other` mangled from what was
        // passed in — a locally-built "optimistic" LangConfig from the same
        // args would echo the args exactly and diverge from this.
        let backend = FakeBackend(config: vi)
        let m = AppModel(backend: backend)
        m.loadConfig()
        m.pick(.target, code: "en")
        XCTAssertEqual(m.config?.other, "en-repaired", "must render what setLangConfig returned, not a guess built from the args")
    }
}
