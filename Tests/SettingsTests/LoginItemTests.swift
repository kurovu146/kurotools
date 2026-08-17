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
        // Sai tên file = SMAppService im lặng không tìm thấy agent — nên test này phải đọc
        // THẬT file plist sẽ được bundle, không so hai literal trong code Swift với nhau.
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LoginItemTests.swift -> SettingsTests/
            .deletingLastPathComponent() // SettingsTests/ -> Tests/
            .deletingLastPathComponent() // Tests/ -> repo root
            .appendingPathComponent("Sources/KuroTools/LaunchAgent.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        let label = try XCTUnwrap(plist["Label"] as? String)
        XCTAssertEqual(label, "com.kuro.kurotools.app")
        XCTAssertEqual(SMAppServiceLoginItem.plistName, "\(label).plist")

        let programArguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertEqual(programArguments.first, "/Applications/KuroTools.app/Contents/MacOS/KuroTools")
    }
}
