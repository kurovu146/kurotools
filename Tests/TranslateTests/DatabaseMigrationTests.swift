import XCTest
@testable import Translate

final class DatabaseMigrationTests: XCTestCase {
    private func makeSandbox() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testCopiesTheOldDatabaseWhenTheNewOneIsMissing() throws {
        let support = try makeSandbox()
        let old = support.appendingPathComponent("com.kurovu.ktranslate")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try "OLD".write(to: old.appendingPathComponent("ktranslate.db"), atomically: true, encoding: .utf8)
        try "WAL".write(to: old.appendingPathComponent("ktranslate.db-wal"), atomically: true, encoding: .utf8)
        try "SHM".write(to: old.appendingPathComponent("ktranslate.db-shm"), atomically: true, encoding: .utf8)

        let resolved = DatabaseMigration.resolveDatabase(appSupport: support, fileManager: .default)

        XCTAssertEqual(try String(contentsOf: resolved, encoding: .utf8), "OLD")
        // -wal và -shm phải đi cùng; bỏ lại chúng là mời một db hỏng.
        let wal = resolved.deletingLastPathComponent().appendingPathComponent("ktranslate.db-wal")
        XCTAssertEqual(try String(contentsOf: wal, encoding: .utf8), "WAL")
        let shm = resolved.deletingLastPathComponent().appendingPathComponent("ktranslate.db-shm")
        XCTAssertEqual(try String(contentsOf: shm, encoding: .utf8), "SHM")
    }

    func testNeverOverwritesAnExistingDatabase() throws {
        let support = try makeSandbox()
        let old = support.appendingPathComponent("com.kurovu.ktranslate")
        let new = support.appendingPathComponent("com.kurovu.kurotools")
        for dir in [old, new] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "OLD".write(to: old.appendingPathComponent("ktranslate.db"), atomically: true, encoding: .utf8)
        try "NEW".write(to: new.appendingPathComponent("ktranslate.db"), atomically: true, encoding: .utf8)

        let resolved = DatabaseMigration.resolveDatabase(appSupport: support, fileManager: .default)
        XCTAssertEqual(try String(contentsOf: resolved, encoding: .utf8), "NEW")
    }

    func testReturnsANewPathWhenNothingToMigrate() throws {
        let support = try makeSandbox()
        let resolved = DatabaseMigration.resolveDatabase(appSupport: support, fileManager: .default)
        XCTAssertTrue(resolved.path.contains("com.kurovu.kurotools"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.deletingLastPathComponent().path))
    }

    /// `FileManager` mà `copyItem` thất bại CHỌN LỌC cho một đường dẫn cụ
    /// thể, sau khi để lại một file DỞ DANG ở đích — mô phỏng cách một lần
    /// copy hỏng-giữa-chừng thật sự (đĩa đầy) thường diễn ra, mà không cần
    /// đụng tới dung lượng đĩa hay `ulimit` thật (không portable — xem
    /// [[forcing-partial-write-failure-is-not-portable]]). Mọi đường dẫn
    /// khác đi thẳng tới `super`.
    private final class CopyFailingFileManager: FileManager {
        let failingPath: String
        private(set) var attemptedCopy = false

        init(failingPath: String) {
            self.failingPath = failingPath
            super.init()
        }

        override func copyItem(at srcURL: URL, to dstURL: URL) throws {
            guard dstURL.path == failingPath else {
                try super.copyItem(at: srcURL, to: dstURL)
                return
            }
            attemptedCopy = true
            createFile(atPath: dstURL.path, contents: Data("PARTIAL".utf8))
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        }
    }

    /// M-2 (final review): trước bản vá, `try?` nuốt lỗi `copyItem` cho file
    /// `.db` CHÍNH — một lần copy hỏng-giữa-chừng để lại một file DỞ DANG ở
    /// đích, và guard `fileExists(newDB)` ở ĐẦU hàm coi nó là "đã migrate"
    /// mãi mãi ở lần gọi kế tiếp, dù nội dung thật ra chỉ là rác — mà vẫn
    /// `NSLog("migrated")` như thể đã thành công. Lịch sử tra cứu mất vĩnh
    /// viễn, không bao giờ thử lại.
    func testDoesNotMarkMigrationCompleteWhenTheMainCopyFails() throws {
        let support = try makeSandbox()
        let old = support.appendingPathComponent("com.kurovu.ktranslate")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try "OLD".write(to: old.appendingPathComponent("ktranslate.db"), atomically: true, encoding: .utf8)

        let newDBPath = support.appendingPathComponent("com.kurovu.kurotools/ktranslate.db").path
        let failing = CopyFailingFileManager(failingPath: newDBPath)

        let resolved = DatabaseMigration.resolveDatabase(appSupport: support, fileManager: failing)

        XCTAssertTrue(failing.attemptedCopy, "the fake must actually have been exercised")
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolved.path),
            "a failed copy must not leave the partial file behind for the next launch's guard to mistake for a completed migration")

        // Lần gọi SAU, với FileManager THẬT (không còn ép lỗi), phải thử lại
        // migration thay vì bị khoá cứng vào lần thất bại trước.
        let retried = DatabaseMigration.resolveDatabase(appSupport: support, fileManager: .default)
        XCTAssertEqual(try String(contentsOf: retried, encoding: .utf8), "OLD",
            "a later launch must be able to retry the migration that failed before")
    }
}
