import XCTest
@testable import Wallpaper
@testable import WallpaperSaver

/// Hai tiến trình tính đường dẫn theo hai công thức khác nhau (app dựng path
/// container từ $HOME; saver chỉ hỏi `applicationSupportDirectory` vì trong
/// sandbox `NSHomeDirectory()` ĐÃ trỏ vào container). Không có gì trong trình
/// biên dịch giữ hai công thức đó khớp nhau — test này là thứ duy nhất giữ.
final class SaverVideoLocatorTests: XCTestCase {
    func testAppSideAndSaverSideResolveToTheSameFolder() {
        let home = URL(fileURLWithPath: "/Users/test")
        let saverApplicationSupport = home
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent("com.apple.ScreenSaver.Engine.legacyScreenSaver")
            .appendingPathComponent("Data/Library/Application Support")

        XCTAssertEqual(
            SaverVideoPaths.containerAppSupport(home: home).standardizedFileURL,
            SaverVideoLocator.folder(inApplicationSupport: saverApplicationSupport).standardizedFileURL,
            "app copy vào một chỗ mà saver tìm ở chỗ khác = màn hình đen, không có lỗi nào báo")
    }

    func testFindReturnsTheInstalledVideoWhateverItsExtension() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("saver-locator-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }

        let folder = SaverVideoLocator.folder(inApplicationSupport: base)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let video = folder.appendingPathComponent("screensaver-video.mov")
        try "x".write(to: video, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            SaverVideoLocator.find(inApplicationSupport: base)?.standardizedFileURL,
            video.standardizedFileURL
        )
    }

    func testFindReturnsNilWhenNothingWasInstalled() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("saver-locator-empty-\(UUID().uuidString)")
        XCTAssertNil(SaverVideoLocator.find(inApplicationSupport: base))
    }
}
