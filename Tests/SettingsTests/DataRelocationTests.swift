import XCTest
@testable import Settings

/// Store giả: ghi lại đúng thứ tự lời gọi, vì thứ tự CHÍNH LÀ tính đúng đắn
/// ở đây (đóng trước khi copy, mở lại sau khi copy).
private final class FakeStore: StoreMaintaining {
    var calls: [String] = []
    var openPaths: [URL] = []
    var failOpenAt: URL?
    var readable = true

    func closeStore() -> Bool { calls.append("close"); return true }
    func openStore(at dbPath: URL) -> Bool {
        calls.append("open")
        openPaths.append(dbPath)
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
    }

    func testMovingToTheSameDirectoryIsRefused() throws {
        let store = FakeStore()
        let outcome = DataRelocation.relocate(
            currentDB: currentDB, toDirectory: oldDir, store: store,
            fileManager: .default, verdict: { _ in .ok }, now: Date())

        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertEqual(store.calls, [])
    }
}
