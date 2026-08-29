import AppKit
import XCTest
import Wallpaper
@testable import KuroTools

/// Mục "Hình nền video" trong dropdown menu bar phải THẬT SỰ bị khoá khi chưa
/// chọn video.
///
/// Bản trước gán `wallpaperItem.isEnabled = false` rồi coi như xong. Đo được
/// (`NSMenu.update()`, đúng lượt AppKit chạy trước khi dropdown hiện): mục có
/// `target` + `action` hợp lệ mà chủ nó không implement `validateMenuItem` thì
/// cờ đó bị GHI ĐÈ THÀNH `true` — bấm được, `setEnabled(true)` persist một
/// preference ẩn, `rebuild()` bail vì chưa có video, và người dùng không nhận
/// được phản hồi nào.
///
/// `menu.update()` chỉ chạy lượt validation khi `NSApplication.shared` đã tồn
/// tại — không có nó, cờ giữ nguyên và test xanh giả ngay cả trên code hỏng.
@MainActor
final class MenuItemValidationTests: XCTestCase {
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        suiteName = "kurotools.menu.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Wallpaper thật nhưng đọc từ suite của riêng test: `videoURL` phải là thứ
    /// test dựng, không phải video người dùng đang thật sự lưu trên máy.
    private func makeDelegate(videoPath: String?) throws -> AppDelegate {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        if let videoPath {
            defaults.set(videoPath, forKey: WallpaperSettingsStore.videoPathKey)
        }
        return AppDelegate(
            wallpaper: VideoWallpaperController(store: WallpaperSettingsStore(defaults: defaults)))
    }

    /// Dựng menu y như `VitalsController` làm rồi chạy lượt validation.
    private func wallpaperItem(in delegate: AppDelegate) throws -> NSMenuItem {
        let menu = NSMenu()
        for item in delegate.makeExtraMenuItems() { menu.addItem(item) }
        menu.update()
        return try XCTUnwrap(menu.items.first { $0.title.hasPrefix("Hình nền video") })
    }

    func testTheWallpaperItemStaysDisabledWhenNoVideoIsChosen() throws {
        let item = try wallpaperItem(in: try makeDelegate(videoPath: nil))

        XCTAssertEqual(item.title, "Hình nền video — chưa chọn video")
        XCTAssertFalse(item.isEnabled,
                       "AppKit bật lại mọi mục có target respond được selector — khoá phải đi qua validateMenuItem")
    }

    func testTheWallpaperItemIsClickableOnceAVideoIsChosen() throws {
        let item = try wallpaperItem(in: try makeDelegate(videoPath: "/tmp/clip.mp4"))

        XCTAssertEqual(item.title, "Hình nền video")
        XCTAssertTrue(item.isEnabled,
                      "khoá quá tay còn tệ hơn: đã chọn video thì công tắc phải bấm được")
    }

    /// Mục tra từ đứng cùng menu và KHÔNG được dính đạn lạc: `validateMenuItem`
    /// chỉ được phán quyết đúng selector của nó.
    func testTheLookupItemIsUntouchedByTheWallpaperRule() throws {
        let delegate = try makeDelegate(videoPath: nil)
        let menu = NSMenu()
        for item in delegate.makeExtraMenuItems() { menu.addItem(item) }
        menu.update()

        let lookup = try XCTUnwrap(menu.items.first { !$0.title.hasPrefix("Hình nền video") })
        XCTAssertTrue(lookup.isEnabled)
    }
}
