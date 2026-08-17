import XCTest
@testable import Settings

/// Bản giả để test logic bật/tắt. `SMAppService` thật đăng ký với launchd —
/// gọi nó trong test sẽ sửa máy đang chạy.
private final class FakeLoginItem: LoginItemControlling {
    var enabled = false
    var failNext = false
    var isEnabled: Bool { enabled }
    func setEnabled(_ on: Bool) throws {
        if failNext { throw NSError(domain: "test", code: 1) }
        enabled = on
    }
}

final class LoginItemTests: XCTestCase {
    func testTogglingOnAndOff() throws {
        let item = FakeLoginItem()
        try item.setEnabled(true)
        XCTAssertTrue(item.isEnabled)
        try item.setEnabled(false)
        XCTAssertFalse(item.isEnabled)
    }

    func testAFailedRegistrationLeavesTheStateUnchanged() {
        let item = FakeLoginItem()
        item.failNext = true
        XCTAssertThrowsError(try item.setEnabled(true))
        XCTAssertFalse(item.isEnabled,
                       "trạng thái phải đọc từ hệ thống, không phải từ ý định của UI")
    }

    func testThePlistNameMatchesTheLabelInsideTheBundledPlist() throws {
        // Sai tên file = SMAppService im lặng không tìm thấy agent.
        XCTAssertEqual(SMAppServiceLoginItem.plistName, "com.kuro.kurotools.app.plist")
    }
}
