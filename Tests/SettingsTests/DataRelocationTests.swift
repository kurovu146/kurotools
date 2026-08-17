import XCTest
@testable import Settings

/// Store giả: ghi lại đúng thứ tự lời gọi, vì thứ tự CHÍNH LÀ tính đúng đắn
/// ở đây (đóng trước khi copy, mở lại sau khi copy).
private final class FakeStore: StoreMaintaining {
    var calls: [String] = []
    var openPaths: [URL] = []
    var failOpenAt: URL?
    /// Fail mở ở MỌI đường dẫn — dùng để dựng ca "rollback cũng không mở lại được".
    var failOpenAlways = false
    var readable = true
    var closeSucceeds = true

    func closeStore() -> Bool { calls.append("close"); return closeSucceeds }
    func openStore(at dbPath: URL) -> Bool {
        calls.append("open")
        openPaths.append(dbPath)
        if failOpenAlways { return false }
        return dbPath != failOpenAt
    }
    func canRead() -> Bool { calls.append("read"); return readable }
}

final class DataRelocationTests: XCTestCase {
    private var tmp: URL!
    private var oldDir: URL!
    private var currentDB: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        oldDir = tmp.appendingPathComponent("old")
        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        currentDB = oldDir.appendingPathComponent("ktranslate.db")
        try Data("payload".utf8).write(to: currentDB)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func newDir(_ name: String = "new") throws -> URL {
        let dir = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testHappyPathCopiesVerifiesThenRenamesTheOldFile() throws {
        let target = try newDir()
        let store = FakeStore()

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .ok },
            now: Date(timeIntervalSince1970: 0))

        let newDB = target.appendingPathComponent("ktranslate.db")
        guard case .moved(let to, let oldRenamedTo) = outcome else {
            return XCTFail("expected .moved, got \(outcome)")
        }
        XCTAssertEqual(to, newDB)
        XCTAssertEqual(try Data(contentsOf: newDB), Data("payload".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: currentDB.path),
                       "file cũ phải được đổi tên, không để nguyên chỗ cũ")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldRenamedTo.path),
                      "file cũ phải còn tồn tại dưới tên mới — không bao giờ xoá")
        XCTAssertEqual(store.calls, ["close", "open", "read"])
        XCTAssertEqual(store.openPaths, [newDB])
    }

    func testARejectedLocationNeverTouchesTheStore() throws {
        let target = try newDir()
        let store = FakeStore()

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .cloudSynced("Dropbox") },
            now: Date())

        XCTAssertEqual(outcome, .rejected(.cloudSynced("Dropbox")))
        XCTAssertEqual(store.calls, [], "không được đóng store khi còn chưa bắt đầu")
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDB.path))
    }

    func testAnExistingDatabaseAtTheDestinationIsRefused() throws {
        let target = try newDir()
        try Data("other".utf8).write(to: target.appendingPathComponent("ktranslate.db"))
        let store = FakeStore()

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .ok }, now: Date())

        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("ktranslate.db")),
                       Data("other".utf8), "file sẵn có ở đích không được đụng tới")
        XCTAssertEqual(store.calls, [])
    }

    func testWhenTheNewStoreCannotBeReadItRollsBackToTheOldPath() throws {
        let target = try newDir()
        let store = FakeStore()
        store.readable = false

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .ok }, now: Date())

        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDB.path),
                      "db cũ phải còn nguyên chỗ cũ")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: target.appendingPathComponent("ktranslate.db").path),
            "bản copy dở dang phải bị dọn")
        XCTAssertEqual(store.openPaths.last, currentDB,
                       "lần mở cuối cùng phải là đường dẫn CŨ")
    }

    func testWhenTheNewStoreCannotBeOpenedItRollsBack() throws {
        let target = try newDir()
        let store = FakeStore()
        store.failOpenAt = target.appendingPathComponent("ktranslate.db")

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .ok }, now: Date())

        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertEqual(store.openPaths.last, currentDB)
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDB.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: target.appendingPathComponent("ktranslate.db").path),
            "bản copy dở dang phải bị dọn ngay cả khi lỗi là không MỞ được, không chỉ không đọc được")
    }

    func testCompanionFilesAreRenamedAlongsideTheDatabaseOnSuccess() throws {
        let target = try newDir()
        try Data("wal".utf8).write(to: URL(fileURLWithPath: currentDB.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: currentDB.path + "-shm"))
        let store = FakeStore()

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .ok },
            now: Date(timeIntervalSince1970: 0))

        guard case .moved = outcome else { return XCTFail("expected .moved, got \(outcome)") }

        let newDB = target.appendingPathComponent("ktranslate.db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDB.path + "-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDB.path + "-shm"))

        let oldEntries = try FileManager.default.contentsOfDirectory(atPath: oldDir.path)
        XCTAssertEqual(oldEntries.count, 3, "db + wal + shm cũ phải đều còn lại, đã đổi tên: \(oldEntries)")
        XCTAssertTrue(oldEntries.allSatisfy { $0.contains(".moved-") },
                      "thư mục cũ không được còn file nào MANG TÊN GỐC — thấy: \(oldEntries)")
    }

    func testAnUnwritableDestinationNeverTouchesTheStore() throws {
        let target = try newDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: target.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path) }
        let store = FakeStore()

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .ok }, now: Date())

        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertEqual(store.calls, [], "thư mục đích không ghi được thì không được đụng tới store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDB.path))
    }

    func testWhenTheRollbackCannotReopenTheOldPathTheStoreEndsUpClosed() throws {
        let target = try newDir()
        let store = FakeStore()
        store.failOpenAlways = true

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .ok }, now: Date())

        guard case .failedAndStoreClosed = outcome else {
            return XCTFail("expected .failedAndStoreClosed, got \(outcome)")
        }
        XCTAssertEqual(store.calls, ["close", "open", "close", "open"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentDB.path),
                      "file cũ không được đụng vào dù store không mở lại được")
    }

    func testWhenTheStoreFailsToCloseNothingIsCopied() throws {
        let target = try newDir()
        let store = FakeStore()
        store.closeSucceeds = false

        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: target, store: store,
            fileManager: .default, verdict: { _ in .ok }, now: Date())

        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: target.appendingPathComponent("ktranslate.db").path),
            "không được copy khi chưa chắc store đã đóng")
        XCTAssertEqual(store.calls, ["close"])
    }

    func testMovingToTheSameDirectoryIsRefused() throws {
        let store = FakeStore()
        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: oldDir, store: store,
            fileManager: .default, verdict: { _ in .ok }, now: Date())

        // So bằng LÝ DO cụ thể, không chỉ `case .failed`: nếu guard so-trùng-
        // thư-mục bị xoá, hàm vẫn trả `.failed` (nhờ guard "đã có db ở đích"
        // phía sau bắt trúng — target khi đó CHÍNH LÀ currentDB) nên
        // `case .failed = outcome` không phân biệt được hai lý do khác nhau.
        XCTAssertEqual(outcome, .failed("Thư mục đích trùng chỗ hiện tại."))
        XCTAssertEqual(store.calls, [])
    }
}
