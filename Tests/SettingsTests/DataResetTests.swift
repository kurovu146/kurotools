import XCTest
@testable import Settings
@testable import Translate

private final class SpyBackend: TranslateBackend {
    var calls: [String] = []
    /// Cờ để dựng ca "backend báo thất bại" — mặc định `true` để các test cũ
    /// (chỉ quan tâm thứ tự gọi) không phải set gì thêm.
    var clearHistorySucceeds = true
    var clearSavedWordsSucceeds = true
    var openStoreSucceeds = true
    /// Ghi lại đường dẫn THẬT mà `openStore` được gọi với — cần để chứng
    /// minh `.everything` mở lại đúng `defaultDBPath`, không phải `dbPath`
    /// cũ (fix round 2, FIX 1).
    var openedPaths: [URL] = []

    func capture() -> CaptureOutcome { .empty }
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void) {}
    func languages() -> [String] { [] }
    func recentLanguages() -> [String] { [] }
    func langConfig() -> LangConfig? { nil }
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig? { nil }
    func hasAccessibility() -> Bool { true }
    func requestAccessibility() -> Bool { true }
    func ttsAvailable() -> Bool { false }
    func speak(_ text: String) {}
    func isSaved(_ word: String) -> Bool { false }
    func setSaved(_ word: String, saved: Bool) -> Bool { true }

    func clearHistory() -> Bool { calls.append("clearHistory"); return clearHistorySucceeds }
    func clearSavedWords() -> Bool { calls.append("clearSaved"); return clearSavedWordsSucceeds }
    func closeStore() -> Bool { calls.append("close"); return true }
    func openStore(at dbPath: URL) -> Bool {
        calls.append("open")
        openedPaths.append(dbPath)
        return openStoreSucceeds
    }
}

final class DataResetTests: XCTestCase {
    private var tmp: URL!
    private var dbPath: URL!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        dbPath = tmp.appendingPathComponent("ktranslate.db")
        try Data("payload".utf8).write(to: dbPath)
        suiteName = "kurotools.reset.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tmp)
    }

    func testClearingHistoryTouchesNothingElse() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        defaults.set(42, forKey: "thresholdC")

        XCTAssertTrue(reset.perform(.history, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName))

        XCTAssertEqual(backend.calls, ["clearHistory"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath.path))
        XCTAssertEqual(defaults.integer(forKey: "thresholdC"), 42)
    }

    func testClearingSavedWordsTouchesNothingElse() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        XCTAssertTrue(reset.perform(.savedWords, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName))
        XCTAssertEqual(backend.calls, ["clearSaved"])
    }

    func testResettingEverythingDeletesTheFileReopensAndWipesPreferences() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        defaults.set(42, forKey: "thresholdC")

        XCTAssertTrue(reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName))

        XCTAssertEqual(backend.calls, ["close", "open"],
                       "phải đóng trước khi xoá file rồi mở lại — thiếu bước mở lại thì app mất db")
        XCTAssertEqual(defaults.object(forKey: "thresholdC") as? Int, nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath.path),
                       "file cũ đã bị xoá; store mở lại sẽ dựng schema mới")
    }

    // MARK: - Lỗi từ backend không được nuốt

    /// Nếu `clearHistory()` thất bại, `perform` PHẢI trả `false` — nuốt lỗi ở
    /// đây nghĩa là UI báo "đã xoá" trong khi dữ liệu vẫn còn nguyên.
    func testHistoryClearFailureIsReportedNotSwallowed() {
        let backend = SpyBackend()
        backend.clearHistorySucceeds = false
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)

        XCTAssertFalse(reset.perform(.history, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName))
    }

    func testSavedWordsClearFailureIsReportedNotSwallowed() {
        let backend = SpyBackend()
        backend.clearSavedWordsSucceeds = false
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)

        XCTAssertFalse(reset.perform(.savedWords, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName))
    }

    /// Ca nghiêm trọng nhất: nếu mở lại store sau khi wipe thất bại, app còn
    /// lại KHÔNG CÓ db nào đang mở — caller phải biết để báo người dùng khởi
    /// động lại, không phải im lặng coi như xong.
    func testEverythingReopenFailureIsReportedNotSwallowed() {
        let backend = SpyBackend()
        backend.openStoreSucceeds = false
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)

        XCTAssertFalse(reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName))
    }

    // MARK: - Dọn companion file

    /// Journal mode của db là `delete` nên `-wal`/`-shm` thường không tồn
    /// tại — vòng lặp xoá chúng trong `.everything` là phòng thủ. Test nó
    /// vẫn cần, vì phòng thủ không ai đo thì âm thầm ngừng hoạt động lúc nào
    /// không biết.
    func testResettingEverythingDeletesWalAndShmCompanions() throws {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        let walPath = URL(fileURLWithPath: dbPath.path + "-wal")
        let shmPath = URL(fileURLWithPath: dbPath.path + "-shm")
        try Data("wal".utf8).write(to: walPath)
        try Data("shm".utf8).write(to: shmPath)

        XCTAssertTrue(reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName))

        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: walPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmPath.path))
    }

    // MARK: - Không mồ côi db đã relocate

    /// Ca chính của FIX 1 (fix round 2): db đang sống ở một thư mục người
    /// dùng từng tự chuyển tới (`dbPath` ≠ `defaultDBPath`). `.everything`
    /// xoá domain UserDefaults — tức xoá luôn override — nên phải mở lại ở
    /// `defaultDBPath`; mở lại ở `dbPath` cũ sẽ khiến lần khởi động SAU
    /// (không còn override) đi tìm db ở `defaultDBPath` trong khi dữ liệu
    /// thật nằm ở `dbPath` — mồ côi vĩnh viễn, không báo gì cho người dùng.
    func testEverythingReopensAtTheDefaultPathNotTheRelocatedOne() throws {
        let customDir = tmp.appendingPathComponent("custom")
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        let customDB = customDir.appendingPathComponent("ktranslate.db")
        try Data("payload".utf8).write(to: customDB)

        let defaultDB = tmp.appendingPathComponent("default").appendingPathComponent("ktranslate.db")

        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)

        XCTAssertTrue(reset.perform(.everything, dbPath: customDB, defaultDBPath: defaultDB, bundleID: suiteName))

        XCTAssertEqual(backend.openedPaths, [defaultDB],
                       "phải mở lại ở default path — mở lại ở chỗ tuỳ chỉnh cũ sẽ làm mồ côi db đó lần khởi động sau")
        XCTAssertFalse(FileManager.default.fileExists(atPath: customDB.path),
                       "db cũ ở thư mục tuỳ chỉnh phải bị xoá, không được để sót lại")
    }

    /// Ca thường (đa số các test khác trong file này cũng đi qua nhánh này):
    /// db chưa từng bị relocate, `dbPath == defaultDBPath`. Ghi lại tường
    /// minh để không lẫn với ca relocate ở trên.
    func testEverythingReopensAtTheSamePathWhenNeverRelocated() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)

        XCTAssertTrue(reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName))

        XCTAssertEqual(backend.openedPaths, [dbPath])
    }
}
