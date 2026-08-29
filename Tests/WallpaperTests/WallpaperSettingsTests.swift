import XCTest
@testable import Wallpaper

/// Round-trip của `WallpaperSettingsStore` — tách khỏi controller vì controller
/// dựng cửa sổ + AVPlayer thật, không chạy được trong test.
final class WallpaperSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "kurotools.wallpaper.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testEmptyDefaultsMeanDisabledWallpaperWithNoVideo() {
        let settings = WallpaperSettingsStore(defaults: defaults).load()
        XCTAssertFalse(settings.enabled)
        XCTAssertNil(settings.videoURL)
    }

    func testSaveLoadRoundTrip() throws {
        let url = try XCTUnwrap(URL(fileURLWithPath: "/tmp/video.mp4"))
        WallpaperSettingsStore(defaults: defaults)
            .save(WallpaperSettings(videoURL: url, enabled: true))

        let loaded = WallpaperSettingsStore(defaults: defaults).load()
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.videoURL, url)
    }

    func testSavingNilVideoClearsThePathButKeepsEnabled() {
        let store = WallpaperSettingsStore(defaults: defaults)
        store.save(WallpaperSettings(videoURL: URL(fileURLWithPath: "/tmp/a.mp4"), enabled: true))
        store.save(WallpaperSettings(videoURL: nil, enabled: true))

        let loaded = WallpaperSettingsStore(defaults: defaults).load()
        XCTAssertNil(loaded.videoURL, "bỏ video phải xoá path, không để chuỗi rỗng")
        XCTAssertTrue(loaded.enabled)
    }

    func testDisablingKeepsTheVideoForLater() throws {
        let store = WallpaperSettingsStore(defaults: defaults)
        let url = try XCTUnwrap(URL(fileURLWithPath: "/tmp/video.mp4"))
        store.save(WallpaperSettings(videoURL: url, enabled: true))
        store.save(WallpaperSettings(videoURL: url, enabled: false))

        let loaded = WallpaperSettingsStore(defaults: defaults).load()
        XCTAssertFalse(loaded.enabled)
        XCTAssertEqual(loaded.videoURL, url,
                       "tắt wallpaper không được quên video — bật lại phải dùng lại được ngay")
    }
}
