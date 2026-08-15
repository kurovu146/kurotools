import XCTest
import AppKit
@testable import Translate

final class PanelSizingTests: XCTestCase {
    func testHeightClampsToTheAllowedRange() {
        let tall = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 900))
        XCTAssertEqual(measuredHeight(of: tall, clampedTo: 90...520), 520)
        let tiny = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 10))
        XCTAssertEqual(measuredHeight(of: tiny, clampedTo: 90...520), 90)
    }

    func testHeightFollowsContentInsideTheRange() {
        let mid = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        XCTAssertEqual(measuredHeight(of: mid, clampedTo: 90...520), 240)
    }
}
