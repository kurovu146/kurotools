import XCTest
@testable import Settings
@testable import Translate

/// Backend giả cho phần vòng đời store: `langConfig()` là phép ĐỌC THẬT mà
/// `canRead()` dựa vào, nên nó có cờ riêng.
private final class MaintenanceBackend: TranslateBackend {
    var config: LangConfig? = LangConfig(source: nil, target: "vi", other: "en")
    var openSucceeds = true
    var closeSucceeds = true
    var openedPaths: [URL] = []

    func capture() -> CaptureOutcome { .empty }
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void) {}
    func languages() -> [String] { [] }
    func recentLanguages() -> [String] { [] }
    func langConfig() -> LangConfig? { config }
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig? { config }
    func hasAccessibility() -> Bool { true }
    func requestAccessibility() -> Bool { true }
    func ttsAvailable() -> Bool { false }
    func speak(_ text: String) {}
    func isSaved(_ word: String) -> Bool { false }
    func setSaved(_ word: String, saved: Bool) -> Bool { true }

    func closeStore() -> Bool { closeSucceeds }
    func openStore(at dbPath: URL) -> Bool {
        openedPaths.append(dbPath)
        return openSucceeds
    }
    func clearHistory() -> Bool { true }
    func clearSavedWords() -> Bool { true }
}

/// Đo hai thứ mà đường đổi chỗ db dựa vào để nói "đã chuyển xong":
/// `OpenFileProbe` (tiến trình này có đang giữ ĐÚNG file đó không) và
/// `BackendStoreMaintenance` (store còn sống và đang giữ file MỚI).
final class BackendStoreMaintenanceTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - OpenFileProbe

    func testTheProbeSeesAFileThisProcessHasOpen() throws {
        let file = tmp.appendingPathComponent("open.db")
        try Data("x".utf8).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        XCTAssertEqual(OpenFileProbe.processHasOpen(file), true)
    }

    func testTheProbeDoesNotSeeAFileNobodyOpened() throws {
        let file = tmp.appendingPathComponent("closed.db")
        try Data("x".utf8).write(to: file)

        XCTAssertEqual(OpenFileProbe.processHasOpen(file), false)
    }

    /// So theo (device, inode), KHÔNG theo chuỗi đường dẫn: `/var/folders/…`
    /// và `/private/var/folders/…` là cùng một file mà `resolvingSymlinksInPath()`
    /// không chuẩn hoá về nhau (đã đo trên máy này) — một phép so chuỗi sẽ báo
    /// "không mở" cho đúng file đang mở, tức từ chối mọi lần đổi chỗ db.
    func testTheProbeMatchesTheSameFileThroughADifferentPath() throws {
        let file = tmp.appendingPathComponent("aliased.db")
        try Data("x".utf8).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        let link = tmp.appendingPathComponent("link.db")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertEqual(OpenFileProbe.processHasOpen(link), true)
    }

    func testTheProbeReportsFalseForAFileThatDoesNotExist() {
        XCTAssertEqual(OpenFileProbe.processHasOpen(tmp.appendingPathComponent("nope.db")), false)
    }

    // MARK: - BackendStoreMaintenance

    func testCanReadIsFalseWhenTheStoreIsDown() throws {
        let backend = MaintenanceBackend()
        backend.config = nil   // `kt_lang_config` trả nil = không đọc được gì
        let maintenance = BackendStoreMaintenance(backend: backend)

        XCTAssertFalse(maintenance.canRead())
    }

    /// 🔑 Giới hạn được kế thừa từ review Task 5: `langConfig() != nil` chỉ
    /// chứng minh store SỐNG, nó qua y hệt khi store vẫn đang mở db CŨ. Kiểm
    /// thêm rằng tiến trình đang thật sự giữ file ở đường dẫn vừa mở mới phân
    /// biệt được hai ca đó.
    func testCanReadIsFalseWhenTheStoreIsAliveButNotHoldingTheNewFile() throws {
        let newDB = tmp.appendingPathComponent("new.db")
        try Data("x".utf8).write(to: newDB)   // file có thật, nhưng không ai mở nó
        let backend = MaintenanceBackend()
        let maintenance = BackendStoreMaintenance(backend: backend)

        XCTAssertTrue(maintenance.openStore(at: newDB))

        XCTAssertFalse(maintenance.canRead(),
                       "store sống nhưng không giữ file mới = nó vẫn đang đọc db cũ")
    }

    func testCanReadIsTrueWhenTheStoreIsAliveAndHoldingTheNewFile() throws {
        let newDB = tmp.appendingPathComponent("held.db")
        try Data("x".utf8).write(to: newDB)
        let handle = try FileHandle(forReadingFrom: newDB)   // đóng vai connection đang mở
        defer { try? handle.close() }
        let backend = MaintenanceBackend()
        let maintenance = BackendStoreMaintenance(backend: backend)

        XCTAssertTrue(maintenance.openStore(at: newDB))

        XCTAssertTrue(maintenance.canRead())
    }

    /// Chưa mở gì qua adapter (đường `relocate` chưa tới bước `openStore`, hay
    /// caller chỉ hỏi store còn sống không) thì chỉ còn phép kiểm sống — không
    /// có đường dẫn nào để đối chiếu.
    func testCanReadFallsBackToTheLivenessCheckBeforeAnythingWasOpened() {
        let maintenance = BackendStoreMaintenance(backend: MaintenanceBackend())

        XCTAssertTrue(maintenance.canRead())
    }

    func testAFailedOpenDoesNotLeaveAPathToVerifyAgainst() throws {
        let backend = MaintenanceBackend()
        backend.openSucceeds = false
        let maintenance = BackendStoreMaintenance(backend: backend)

        XCTAssertFalse(maintenance.openStore(at: tmp.appendingPathComponent("never.db")))

        XCTAssertTrue(maintenance.canRead(),
                      "openStore thất bại thì rollback mới là việc tiếp theo, không phải một phép kiểm file")
    }

    // MARK: - Đối chứng trên FFI THẬT

    /// Giả định chống đỡ toàn bộ phép kiểm ở trên: một `Store` của Rust
    /// (rusqlite `Connection::open`) giữ file db mở suốt vòng đời connection,
    /// nên `OpenFileProbe` PHẢI nhìn thấy nó. Sai giả định này thì `canRead()`
    /// sẽ từ chối MỌI lần đổi chỗ db thành công — nên nó cần một test thật,
    /// không phải một lời khẳng định trong comment.
    func testARealStoreOpenedThroughTheBridgeIsSeenHoldingItsFile() throws {
        let bridge = KTranslateBridge()
        // `STORE` phía Rust là global cấp tiến trình và `kt_init` là no-op
        // thành công khi đã có store mở — cùng lý do với `StoreMaintenanceTests`.
        _ = bridge.closeStore()
        defer { _ = bridge.closeStore() }

        let dbPath = tmp.appendingPathComponent("real.db")
        let maintenance = BackendStoreMaintenance(backend: bridge)

        XCTAssertTrue(maintenance.openStore(at: dbPath))

        XCTAssertEqual(OpenFileProbe.processHasOpen(dbPath), true,
                       "rusqlite phải đang giữ file này mở")
        XCTAssertTrue(maintenance.canRead())
    }
}
