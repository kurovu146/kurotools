import XCTest
@testable import Translate

final class ToggleDecisionTests: XCTestCase {
    /// I-1 follow-up (final review): capture off main thread means the popup
    /// only shows inside captureAsync's completion, so isPanelVisible stays
    /// false throughout the whole in-flight wait. A second hotkey press
    /// during that window must be coalesced into the request already flying,
    /// not read as "show" again.
    func testIgnoresTheHotkeyWhileACaptureIsInFlight() {
        XCTAssertEqual(decideToggle(isCapturing: true, isPanelVisible: false), .ignore)
        XCTAssertEqual(decideToggle(isCapturing: true, isPanelVisible: true), .ignore)
    }

    func testShowsWhenIdleAndHidden() {
        XCTAssertEqual(decideToggle(isCapturing: false, isPanelVisible: false), .show)
    }

    func testHidesWhenIdleAndVisible() {
        XCTAssertEqual(decideToggle(isCapturing: false, isPanelVisible: true), .hide)
    }
}
