import AppKit
import XCTest
import TestSupport
@testable import Settings

/// Login item giả — cùng khuôn với `StubLoginItem` của `SettingsModelTests`,
/// nhưng lớp này cần một instance DÙNG CHUNG (xem `sharedModel()`).
private final class StubLoginItem: LoginItemControlling {
    var current: LoginItemState = .off
    var state: LoginItemState { current }
    func setEnabled(_ on: Bool) throws { current = on ? .on : .off }
}

/// Cửa sổ Settings có hai bất biến mà spec gọi tên thẳng — §4 "một instance
/// duy nhất (⌘, hai lần không mở hai cửa sổ)" và bản vá Task 12 bắt nó đọc lại
/// trạng thái hệ thống ở MỖI lần mở — và trước lớp này không có test nào chạm
/// tới `SettingsWindowController`: gỡ CẢ HAI ra khỏi `show()` vẫn để 180 test
/// xanh.
///
/// ⚠️ Cả lớp dùng CHUNG một `SettingsModel`, có chủ ý.
/// `SettingsWindowController.shared` là static và sống suốt tiến trình test;
/// `show(model:)` gọi `assertionFailure` khi nhận một model KHÁC model cửa sổ
/// đang bọc, và trap đó giết cả lần `swift test`, không riêng một test. Nhánh
/// đó cố tình KHÔNG được test ở đây.
@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    private static let loginItem = StubLoginItem()
    private static var model: SettingsModel?
    private static var suiteName = ""

    override func setUp() {
        // `show()` gọi `NSApp.activate(ignoringOtherApps: true)`. `.prohibited`
        // giữ tiến trình test KHÔNG bao giờ trở thành app active — một bộ test
        // giành focus của máy đang dùng là không chấp nhận được. Cửa sổ vẫn
        // dựng và `isVisible` vẫn đúng (đã đo).
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    private func sharedModel() -> SettingsModel {
        if let model = Self.model { return model }
        let (defaults, suite) = PreferencesSandbox.make("settings-window")
        Self.suiteName = suite
        let model = SettingsModel.forTesting(
            loginItem: Self.loginItem, defaults: defaults, bundleID: suite)
        Self.model = model
        return model
    }

    private func settingsWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.title == "KuroTools Settings" }
    }

    /// Spec §4: bấm ⌘, lần thứ hai phải mang cửa sổ đang mở lên trước.
    func testASecondShowReusesTheSameWindow() throws {
        let model = sharedModel()

        SettingsWindowController.show(model: model)
        let first = try XCTUnwrap(settingsWindows().first)
        XCTAssertEqual(settingsWindows().count, 1)

        SettingsWindowController.show(model: model)

        let after = settingsWindows()
        XCTAssertEqual(after.count, 1,
                       "lần mở thứ hai dựng thêm cửa sổ — hai bản Settings cùng sống, mỗi bản một bản sao trạng thái")
        XCTAssertTrue(after.first === first,
                      "phải là đúng object cũ, không phải một cửa sổ mới tình cờ trùng tiêu đề")
    }

    /// Task 12: giữa hai lần mở, người dùng có thể đã tắt login item trong
    /// System Settings, đổi cặp ngôn ngữ từ popup tra từ, hay bị app khác
    /// giành mất phím tắt. `.onAppear` của root view chỉ chạy đúng MỘT lần cho
    /// cả vòng đời app (`close()` order-out chứ không tháo content view), nên
    /// `show()` mới là chỗ nạp lại.
    func testEveryShowRereadsTheSystemState() {
        let model = sharedModel()
        Self.loginItem.current = .off
        SettingsWindowController.show(model: model)
        XCTAssertEqual(model.loginItemState, .off, "setup")

        // Người dùng bật login item ở System Settings sau lưng cửa sổ này.
        Self.loginItem.current = .on
        SettingsWindowController.show(model: model)

        XCTAssertEqual(model.loginItemState, .on,
                       "mở lại cửa sổ mà vẫn hiện bản nạp lần trước là đúng bug `.onAppear` chỉ chạy một lần")
    }

    /// 🔑 Fix wave cuối M2 (FIX 3). Luồng duyệt đi RA KHỎI app: bật công tắc →
    /// "cần duyệt" + nút Mở → System Settings → duyệt → quay lại đúng cửa sổ
    /// vẫn đang mở. Không `show()` nào xảy ra trên đường về, nên dòng "còn một
    /// bước" nằm lại sau khi bước đó đã xong — hỏng đúng luồng duy nhất mà
    /// `.requiresApproval` tồn tại để phục vụ.
    func testTheWindowRereadsTheSystemStateWhenTheAppBecomesActiveAgain() {
        let model = sharedModel()
        Self.loginItem.current = .requiresApproval
        SettingsWindowController.show(model: model)
        XCTAssertEqual(model.loginItemState, .requiresApproval, "setup")

        // Người dùng duyệt trong System Settings rồi quay lại app.
        Self.loginItem.current = .on
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: NSApp)

        XCTAssertEqual(model.loginItemState, .on,
                       "quay lại app sau khi duyệt mà UI vẫn nói 'còn một bước' là bug FIX 3")
    }

    /// Mặt còn lại của cùng observer: `refreshFromSystem()` đọc xuống FFI và
    /// app nhận `didBecomeActive` mỗi lần người dùng chạm vào menu bar hay
    /// popup tra từ. Cửa sổ đã đóng thì không có ai nhìn kết quả.
    func testTheActivationRefreshIsSkippedWhileTheWindowIsClosed() throws {
        let model = sharedModel()
        Self.loginItem.current = .off
        SettingsWindowController.show(model: model)
        try XCTUnwrap(settingsWindows().first).close()
        XCTAssertEqual(model.loginItemState, .off, "setup")

        Self.loginItem.current = .on
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: NSApp)

        XCTAssertEqual(model.loginItemState, .off,
                       "cửa sổ đóng thì không nạp lại — lần `show()` kế tiếp mới là lúc cần đọc hệ thống")
    }
}
