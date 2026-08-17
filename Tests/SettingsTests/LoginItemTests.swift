import XCTest
@testable import Settings

/// Bản giả để test logic bật/tắt. `SMAppService` thật đăng ký với launchd —
/// gọi nó trong test sẽ sửa máy đang chạy. `state` là `var` công khai để test
/// gán thẳng `.requiresApproval` — trạng thái đó không đi qua `setEnabled`.
private final class FakeLoginItem: LoginItemControlling {
    var state: LoginItemState = .off
    var failNext = false
    func setEnabled(_ on: Bool) throws {
        if failNext { throw NSError(domain: "test", code: 1) }
        state = on ? .on : .off
    }
}

/// Cả hai test đọc file thật bên dưới cần leo từ file test này lên gốc repo.
private func repoRoot(from testFile: String = #filePath) -> URL {
    URL(fileURLWithPath: testFile)
        .deletingLastPathComponent() // LoginItemTests.swift -> SettingsTests/
        .deletingLastPathComponent() // SettingsTests/ -> Tests/
        .deletingLastPathComponent() // Tests/ -> repo root
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

    func testARequiresApprovalStateIsReportedAsSuchNotAsOff() {
        // `register()` không throw khi macOS xếp hàng "background item added";
        // UI đọc lại `state` phải thấy đúng `.requiresApproval`, không được
        // gộp chung với `.off` rồi bật công tắc về lại vị trí cũ trong im lặng.
        let item = FakeLoginItem()
        item.state = .requiresApproval
        XCTAssertEqual(item.state, .requiresApproval)
        XCTAssertFalse(item.isEnabled,
                       "chờ duyệt chưa phải bật, nhưng không được lẫn với off")
    }

    func testThePlistNameMatchesTheLabelInsideTheBundledPlist() throws {
        // Sai tên file = SMAppService im lặng không tìm thấy agent — nên test này phải đọc
        // THẬT file plist sẽ được bundle, không so hai literal trong code Swift với nhau.
        let plistURL = repoRoot().appendingPathComponent("Sources/KuroTools/LaunchAgent.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        let label = try XCTUnwrap(plist["Label"] as? String)
        XCTAssertEqual(label, "com.kuro.kurotools.app")
        XCTAssertEqual(SMAppServiceLoginItem.plistName, "\(label).plist")

        let programArguments = try XCTUnwrap(plist["ProgramArguments"] as? [String])
        XCTAssertEqual(programArguments.first, "/Applications/KuroTools.app/Contents/MacOS/KuroTools")
    }

    func testTheBundleScriptCopiesThePlistToTheNameSMAppServiceExpects() throws {
        // Fix round 2: đổi MỘT MÌNH tên đích trong bundle-app.sh vẫn để mọi thứ
        // khác xanh (test cũ không đọc script, build/chữ ký không quan tâm tên
        // file). Đọc thật script, bắt dòng `cp` copy plist, ép nó khớp
        // `SMAppServiceLoginItem.plistName` — sai tên = SMAppService không bao
        // giờ tìm thấy agent lúc chạy thật, dù mọi thứ trong CI đều xanh.
        let scriptURL = repoRoot().appendingPathComponent("scripts/bundle-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let copyLine = try XCTUnwrap(
            script.components(separatedBy: .newlines).first {
                $0.hasPrefix("cp ") && $0.contains("LaunchAgent.plist")
            },
            "không tìm thấy dòng `cp ... LaunchAgent.plist` trong bundle-app.sh")

        XCTAssertTrue(
            copyLine.hasSuffix("\(SMAppServiceLoginItem.plistName)\""),
            "đích copy trong bundle-app.sh phải kết thúc bằng đúng " +
            "SMAppServiceLoginItem.plistName (\"\(SMAppServiceLoginItem.plistName)\"); " +
            "dòng thật đọc được: \(copyLine)")
    }
}
