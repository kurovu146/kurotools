import XCTest
import AppKit
@testable import Translate

final class PanelSizingTests: XCTestCase {
    func testHeightIsCappedButNeverFloored() {
        let tall = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 900))
        XCTAssertEqual(measuredHeight(of: tall, clampedTo: 0...520), 520)

        // Không còn sàn: một kết quả ngắn phải cho một panel ngắn, không phải
        // một panel 90pt với dải trống bên dưới.
        let tiny = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 10))
        XCTAssertEqual(measuredHeight(of: tiny, clampedTo: 0...520), 10)
    }

    func testHeightFollowsContentInsideTheRange() {
        let mid = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        XCTAssertEqual(measuredHeight(of: mid, clampedTo: 0...520), 240)
    }

    /// Bảo vệ chính quyết định "bỏ sàn": nếu ai đó đặt lại một `lowerBound`
    /// khác 0, panel lại phình lên cho mọi kết quả ngắn.
    func testTheShippedRangeHasNoFloor() {
        XCTAssertEqual(PopupPanel.contentHeightRange.lowerBound, 0)
        XCTAssertEqual(PopupPanel.contentHeightRange.upperBound, 520)
    }
}
