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

        let resolved = DatabaseMigration.resolveDatabase(appSupport: support, fileManager: .default)

        XCTAssertEqual(try String(contentsOf: resolved, encoding: .utf8), "OLD")
        // -wal và -shm phải đi cùng; bỏ lại chúng là mời một db hỏng.
        let wal = resolved.deletingLastPathComponent().appendingPathComponent("ktranslate.db-wal")
        XCTAssertEqual(try String(contentsOf: wal, encoding: .utf8), "WAL")
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
}
