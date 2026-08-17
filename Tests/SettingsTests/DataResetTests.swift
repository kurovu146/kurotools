import XCTest
import TestSupport
@testable import Settings
@testable import Translate

private final class SpyBackend: TranslateBackend {
    var calls: [String] = []
    /// Cờ để dựng ca "backend báo thất bại" — mặc định `true` để các test cũ
    /// (chỉ quan tâm thứ tự gọi) không phải set gì thêm.
    var clearHistorySucceeds = true
    var clearSavedWordsSucceeds = true
    var openStoreSucceeds = true
    /// 🔑 Bản trước hardcode `true` cho `closeStore` — không test nào dựng
    /// được ca "store không chịu đóng", nên `DataReset` bỏ qua kết quả của nó
    /// suốt mà mọi thứ vẫn xanh.
    var closeStoreSucceeds = true
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
    func closeStore() -> Bool { calls.append("close"); return closeStoreSucceeds }
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
        (defaults, suiteName) = PreferencesSandbox.make("reset")
    }

    override func tearDownWithError() throws {
        PreferencesSandbox.destroy(suiteName)
        try? FileManager.default.removeItem(at: tmp)
    }

    func testClearingHistoryTouchesNothingElse() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        defaults.set(42, forKey: "thresholdC")

        XCTAssertEqual(reset.perform(.history, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName), .done)

        XCTAssertEqual(backend.calls, ["clearHistory"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath.path))
        XCTAssertEqual(defaults.integer(forKey: "thresholdC"), 42)
    }

    func testClearingSavedWordsTouchesNothingElse() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        XCTAssertEqual(reset.perform(.savedWords, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName), .done)
        XCTAssertEqual(backend.calls, ["clearSaved"])
    }

    func testResettingEverythingDeletesTheFileReopensAndWipesPreferences() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        defaults.set(42, forKey: "thresholdC")

        XCTAssertEqual(reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName), .done)

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

        XCTAssertEqual(reset.perform(.history, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName), .failedNothingRemoved)
    }

    func testSavedWordsClearFailureIsReportedNotSwallowed() {
        let backend = SpyBackend()
        backend.clearSavedWordsSucceeds = false
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)

        XCTAssertEqual(reset.perform(.savedWords, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName), .failedNothingRemoved)
    }

    /// Ca nghiêm trọng nhất: nếu mở lại store sau khi wipe thất bại, app còn
    /// lại KHÔNG CÓ db nào đang mở — caller phải biết để báo người dùng khởi
    /// động lại, không phải im lặng coi như xong.
    func testEverythingReopenFailureIsReportedNotSwallowed() {
        let backend = SpyBackend()
        backend.openStoreSucceeds = false
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)

        XCTAssertEqual(reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName), .removedButStoreClosed)
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

        XCTAssertEqual(reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName), .done)

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

        XCTAssertEqual(reset.perform(.everything, dbPath: customDB, defaultDBPath: defaultDB, bundleID: suiteName), .done)

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

        XCTAssertEqual(reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName), .done)

        XCTAssertEqual(backend.openedPaths, [dbPath])
    }

    // MARK: - Fix wave cuối M2 (FIX 4): `closeStore()` là một CỔNG, không phải một lời chào

    /// 🔑 Giao kèo `StoreMaintaining.closeStore()`: `false` = "chưa đóng được
    /// gì cả". Bản trước làm `_ = backend.closeStore()` rồi xoá file luôn —
    /// xoá đúng inode mà Rust vẫn đang giữ. Sau đó `kt_init` là no-op THÀNH
    /// CÔNG (store đã mở sẵn), nên `openStore` trả `true` và model báo "Đã xoá
    /// sạch" trong khi mọi lần tra tiếp theo ghi vào một file đã unlink cho
    /// tới lúc thoát app. `DataRelocation.relocate` gác đúng lời gọi này;
    /// `DataReset` thì không.
    func testAStoreThatWillNotCloseStopsTheWipeBeforeAnythingIsRemoved() throws {
        let backend = SpyBackend()
        backend.closeStoreSucceeds = false
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        let walPath = URL(fileURLWithPath: dbPath.path + "-wal")
        try Data("wal".utf8).write(to: walPath)
        defaults.set(42, forKey: "thresholdC")

        XCTAssertEqual(
            reset.perform(.everything, dbPath: dbPath, defaultDBPath: dbPath, bundleID: suiteName),
            .failedNothingRemoved)

        XCTAssertEqual(backend.calls, ["close"],
                       "dừng ngay sau lời gọi bị từ chối — không được mở lại gì cả")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath.path),
                      "db vẫn đang được giữ mở — xoá file là xoá inode dưới chân driver")
        XCTAssertTrue(FileManager.default.fileExists(atPath: walPath.path))
        XCTAssertEqual(defaults.integer(forKey: "thresholdC"), 42,
                       "chưa xoá được db thì cũng chưa được xoá preference — nửa vời còn tệ hơn không làm")
    }

    // MARK: - Fix wave cuối M2 (FIX 7): db ở chỗ MẶC ĐỊNH cũng phải chết

    /// 🔑 `DataRelocation` cố ý chấp nhận `moveItem` thất bại: db mới đã chạy
    /// rồi, không đổi tên được bản cũ chỉ là phiền — nên `ktranslate.db` nằm
    /// lại ở chỗ mặc định. "Xoá sạch" từ chỗ đã chuyển tới sẽ xoá db ở
    /// `dbPath` rồi mở lại ở `defaultDBPath`, hạ cánh đúng lên bản cũ còn
    /// sống: UI nói "Đã xoá sạch", người dùng đã gõ XOÁ, và toàn bộ lịch sử
    /// cũ vẫn còn đó.
    func testEverythingAlsoRemovesASurvivingDatabaseAtTheDefaultPath() throws {
        let customDir = tmp.appendingPathComponent("custom")
        let defaultDir = tmp.appendingPathComponent("default")
        for dir in [customDir, defaultDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let customDB = customDir.appendingPathComponent("ktranslate.db")
        let defaultDB = defaultDir.appendingPathComponent("ktranslate.db")
        try Data("đang dùng".utf8).write(to: customDB)
        // Bản sót lại sau một lần đổi chỗ mà bước đổi tên thất bại.
        try Data("bản cũ còn sống".utf8).write(to: defaultDB)
        let defaultWAL = URL(fileURLWithPath: defaultDB.path + "-wal")
        try Data("wal".utf8).write(to: defaultWAL)

        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)

        XCTAssertEqual(
            reset.perform(.everything, dbPath: customDB, defaultDBPath: defaultDB, bundleID: suiteName),
            .done)

        XCTAssertFalse(FileManager.default.fileExists(atPath: customDB.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultDB.path),
                       "db ở chỗ mặc định là chính chỗ store vừa được mở lại — để nó sống nghĩa là XOÁ SẠCH không xoá gì")
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultWAL.path),
                       "companion đi theo db chính, không được để lại cạnh một db mới")
        XCTAssertEqual(backend.openedPaths, [defaultDB])
    }
}
