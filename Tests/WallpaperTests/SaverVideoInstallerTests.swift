import XCTest
@testable import Wallpaper

/// `SaverVideoInstaller` là toàn bộ phần app-side của cây cầu sang screensaver:
/// nó copy video vào container của `legacyScreenSaver`. Test tiêm thư mục tạm —
/// không test nào được phép chạm container thật của máy.
final class SaverVideoInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("saver-installer-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try super.tearDownWithError()
    }

    /// Nguồn giả: một file có nội dung nhận dạng được, để khẳng định đúng file
    /// đó được copy chứ không phải một file rỗng cùng tên.
    private func makeSource(named name: String, body: String = "video-bytes") throws -> URL {
        let dir = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func installer() -> SaverVideoInstaller {
        SaverVideoInstaller(folder: root.appendingPathComponent("container"))
    }

    func testInstallCopiesVideoUnderTheFixedName() throws {
        let source = try makeSource(named: "download.mp4")
        let installed = try installer().install(source)

        XCTAssertEqual(installed.lastPathComponent, "screensaver-video.mp4",
                       "tên phải cố định — saver tìm theo tên, không theo tên gốc")
        XCTAssertEqual(try String(contentsOf: installed, encoding: .utf8), "video-bytes")
        // Dùng standardizedFileURL để tránh flakiness từ symlink trên macOS
        XCTAssertEqual(installer().installedVideo()?.standardizedFileURL,
                       installed.standardizedFileURL)
    }

    func testInstallingADifferentExtensionLeavesExactlyOneVideo() throws {
        let inst = installer()
        _ = try inst.install(try makeSource(named: "a.mov", body: "old"))
        _ = try inst.install(try makeSource(named: "b.mp4", body: "new"))

        let items = try FileManager.default.contentsOfDirectory(
            at: inst.folder, includingPropertiesForKeys: nil)
        // Dùng standardizedFileURL khi so sánh với contentsOfDirectory
        let standardized = items.map { $0.standardizedFileURL }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        let expected = ["screensaver-video.mp4"]
        XCTAssertEqual(standardized.map { $0.lastPathComponent }, expected,
                       "đổi đuôi mà không dọn bản cũ thì saver có hai file và không biết chọn cái nào")
    }

    func testClearRemovesTheVideoAndIsSafeWhenNothingIsThere() throws {
        let inst = installer()
        _ = try inst.install(try makeSource(named: "a.mp4"))
        try inst.clear()
        XCTAssertNil(inst.installedVideo())

        XCTAssertNoThrow(try inst.clear(), "gọi clear lúc chưa có gì là chuyện bình thường")
    }

    func testInstallingAMissingSourceThrowsAndLeavesNoJunk() throws {
        let inst = installer()
        let ghost = root.appendingPathComponent("src/khong-ton-tai.mp4")

        XCTAssertThrowsError(try inst.install(ghost)) { error in
            XCTAssertEqual(error as? SaverVideoInstallError, .sourceMissing(ghost))
        }
        XCTAssertNil(inst.installedVideo())
    }

    /// 🔑 Copy hỏng GIỮA CHỪNG là ca thật (đầy đĩa, rút ổ ngoài). Bản trước xoá
    /// video cũ TRƯỚC khi copy, nên một lần copy hỏng để lại file cụt ở đúng
    /// chỗ saver đọc — và không còn bản nào để lùi về.
    ///
    /// Dựng ca đó bằng một nguồn không đọc được: `fileExists` vẫn `true` nên
    /// installer đi qua mọi guard rồi mới chết ở đúng bước copy.
    func testAFailedCopyKeepsTheOldVideoInsteadOfLeavingATruncatedOne() throws {
        let fm = FileManager.default
        let inst = installer()
        _ = try inst.install(try makeSource(named: "cu.mp4", body: "video-cu"))

        let unreadable = try makeSource(named: "moi.mp4", body: "video-moi")
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }

        XCTAssertThrowsError(try inst.install(unreadable))

        let installed = try XCTUnwrap(inst.installedVideo(),
                                      "bản cũ phải còn nguyên — copy hỏng không được để container rỗng")
        XCTAssertEqual(try String(contentsOf: installed, encoding: .utf8), "video-cu",
                       "file ở chỗ saver đọc phải là bản cũ NGUYÊN VẸN, không phải bản mới cụt")
        XCTAssertEqual(
            try fm.contentsOfDirectory(at: inst.folder, includingPropertiesForKeys: nil).count, 1,
            "file tạm phải được dọn, không nằm lại trong container")
    }

    /// `fileExists(atPath:)` trả `true` cho thư mục và `copyItem` copy cả cây.
    func testInstallingADirectoryIsRejected() throws {
        let inst = installer()
        let dir = root.appendingPathComponent("src/mot-thu-muc.mp4")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        XCTAssertThrowsError(try inst.install(dir)) { error in
            XCTAssertEqual(error as? SaverVideoInstallError, .sourceIsNotAFile(dir))
        }
        XCTAssertNil(inst.installedVideo())
    }

    /// `SettingsModel` đưa thẳng `localizedDescription` vào dòng trạng thái của
    /// Settings, nên mặc định "error 0" của Swift là thứ người dùng đọc được.
    func testInstallErrorsReadAsSentencesNotErrorCodes() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        for error in [SaverVideoInstallError.sourceMissing(url), .sourceIsNotAFile(url)] {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("clip.mp4"), "phải nói rõ file nào: \(message)")
            XCTAssertFalse(message.contains("error 0"), "mô tả mặc định của Swift lọt ra UI: \(message)")
        }
    }

    func testContainerPathIsBuiltFromHome() {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertEqual(
            SaverVideoPaths.containerAppSupport(home: home).path,
            "/Users/test/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver"
                + "/Data/Library/Application Support/KuroTools")
    }
}
