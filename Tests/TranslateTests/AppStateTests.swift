import XCTest
@testable import Translate

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

    func testBlankTextGoesIdleNotLoading() {
        let m = model(config: nil)
        m.run("   ")
        XCTAssertEqual(m.state, .idle)
    }

    func testNeedsPermissionOutcomeSurfacesTheGate() {
        let m = model(config: nil)
        m.handle(.needsPermission)
        XCTAssertEqual(m.state, .needsPermission)
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
}
