import Carbon.HIToolbox
import XCTest
@testable import Settings
@testable import Translate
@testable import Vitals

/// Login item giả — bám đúng hợp đồng BA TRẠNG THÁI của `LoginItemControlling`
/// (Task 9), không phải một `Bool`. `nextState` cho phép dựng ca
/// `.requiresApproval`: `register()` KHÔNG throw, macOS xếp hàng chờ người
/// dùng duyệt trong System Settings.
private final class StubLoginItem: LoginItemControlling {
    var current: LoginItemState = .off
    /// Trạng thái hệ thống sẽ báo sau một lần `setEnabled(true)` thành công.
    var stateAfterEnabling: LoginItemState = .on
    var shouldThrow = false

    var state: LoginItemState { current }

    func setEnabled(_ on: Bool) throws {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        current = on ? stateAfterEnabling : .off
    }
}

/// Backend im lặng: đủ để dựng `SettingsModel` mà không chạm FFI nào.
/// `clearHistory`/`clearSavedWords`/`closeStore`/`openStore` có cờ riêng để
/// dựng ca thất bại.
private final class StubBackend: TranslateBackend {
    var calls: [String] = []
    var clearHistorySucceeds = true
    var clearSavedWordsSucceeds = true
    var openStoreSucceeds = true
    var openedPaths: [URL] = []
    var config: LangConfig?

    func capture() -> CaptureOutcome { .empty }
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void) {}
    func languages() -> [String] { ["en", "vi"] }
    func recentLanguages() -> [String] { [] }
    func langConfig() -> LangConfig? { config }
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig? { config }
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

/// Store giả cho đường đổi chỗ db — cùng khuôn `FakeStore` của
/// `DataRelocationTests`, thêm `onOpen` để dựng ca TÁI NHẬP (một lời gọi
/// `relocateDatabase` thứ hai bắn ra từ BÊN TRONG lời gọi đầu).
private final class FakeStore: StoreMaintaining {
    var calls: [String] = []
    var openPaths: [URL] = []
    var closeSucceeds = true
    var readable = true
    var openSucceeds: (URL) -> Bool = { _ in true }
    var onOpen: (() -> Void)?

    func closeStore() -> Bool { calls.append("close"); return closeSucceeds }
    func openStore(at dbPath: URL) -> Bool {
        calls.append("open")
        openPaths.append(dbPath)
        onOpen?()
        return openSucceeds(dbPath)
    }
    func canRead() -> Bool { calls.append("read"); return readable }
}

@MainActor
final class SettingsModelTests: XCTestCase {
    private var tmp: URL!
    private var dbPath: URL!
    private var defaultDBPath: URL!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let currentDir = tmp.appendingPathComponent("current")
        try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        dbPath = currentDir.appendingPathComponent("ktranslate.db")
        try Data("payload".utf8).write(to: dbPath)
        defaultDBPath = tmp.appendingPathComponent("default").appendingPathComponent("ktranslate.db")
        suiteName = "kurotools.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tmp)
    }

    /// `translate` là `nil` mặc định chứ không phải `TranslateController()`:
    /// biểu thức mặc định của tham số chạy ở ngữ cảnh nonisolated, mà
    /// `TranslateController.init` là `@MainActor`.
    private func makeModel(
        loginItem: LoginItemControlling = StubLoginItem(),
        backend: TranslateBackend = StubBackend(),
        maintenance: StoreMaintaining? = nil,
        translate: TranslateController? = nil
    ) -> SettingsModel {
        SettingsModel(
            translate: translate ?? TranslateController(),
            vitals: VitalsController(defaults: defaults),
            backend: backend,
            loginItem: loginItem,
            maintenance: maintenance,
            dbPath: dbPath,
            defaultDBPath: defaultDBPath,
            defaults: defaults,
            bundleID: suiteName)
    }

    // MARK: - Chạy khi đăng nhập (ràng buộc 5: ba trạng thái, không phải Bool)

    func testAFailedLoginItemToggleReportsAndSnapsBack() throws {
        let login = StubLoginItem()
        login.shouldThrow = true
        let model = SettingsModel.forTesting(loginItem: login)

        model.setRunAtLogin(true)

        XCTAssertFalse(model.runAtLogin, "công tắc phải bám trạng thái THẬT của hệ thống")
        XCTAssertNotNil(model.status, "thất bại phải nói ra, không im lặng")
    }

    func testASuccessfulLoginItemToggleSticks() {
        let login = StubLoginItem()
        let model = SettingsModel.forTesting(loginItem: login)
        model.setRunAtLogin(true)
        XCTAssertTrue(model.runAtLogin)
        XCTAssertEqual(login.state, .on)
        XCTAssertEqual(model.loginItemState, .on)
    }

    /// 🔑 Ràng buộc 5. `register()` thành công nhưng macOS chờ duyệt trong
    /// System Settings. Hiển thị nó như "tắt" làm công tắc trông như hỏng —
    /// người dùng bấm, thấy nó bật rồi tự tắt, không một lời giải thích.
    func testRequiresApprovalIsItsOwnStateNotOff() {
        let login = StubLoginItem()
        login.stateAfterEnabling = .requiresApproval
        let model = SettingsModel.forTesting(loginItem: login)

        model.setRunAtLogin(true)

        XCTAssertEqual(model.loginItemState, .requiresApproval,
                       "trạng thái chờ duyệt phải giữ nguyên danh tính, không gộp vào .off")
        XCTAssertTrue(model.runAtLogin, "công tắc KHÔNG được tự bật lên rồi tắt lại")
        XCTAssertNotEqual(model.status, nil)
        XCTAssertTrue(model.status?.contains("duyệt") == true,
                      "phải nói cho người dùng biết còn một bước trong System Settings, thấy: \(model.status ?? "nil")")
    }

    /// Người dùng có thể tắt login item trong System Settings mà app không hề
    /// biết — mở lại cửa sổ Settings phải đọc lại hệ thống, không hiện bản
    /// nhớ trong bộ nhớ.
    func testReopeningTheWindowRereadsTheSystemState() {
        let login = StubLoginItem()
        let model = SettingsModel.forTesting(loginItem: login)
        model.setRunAtLogin(true)
        XCTAssertTrue(model.runAtLogin)

        login.current = .off   // người dùng tắt ở System Settings
        model.refreshFromSystem()

        XCTAssertFalse(model.runAtLogin)
        XCTAssertEqual(model.loginItemState, .off)
    }

    // MARK: - Phím tắt (ràng buộc 4: isHotkeyRegistered phải lộ ra)

    /// 🔑 Ràng buộc 4, ca gặp ngay LẦN CHẠY ĐẦU: `currentHotkey` luôn có giá
    /// trị kể cả khi `RegisterEventHotKey` chưa từng chạy hay đã thất bại —
    /// chỉ `isHotkeyRegistered` mới nói tổ hợp đó có thật sự của mình không.
    func testAHotkeyThatWasNeverRegisteredIsNotReportedAsWorking() {
        let model = makeModel()

        XCTAssertEqual(model.hotkey, .default, "vẫn phải hiện tổ hợp đang được cấu hình")
        XCTAssertFalse(model.hotkeyIsRegistered,
                       "chưa đăng ký với hệ thống thì không được báo là đang hoạt động")
    }

    func testAHotkeyThatIsReallyRegisteredIsReportedAsWorking() {
        let controller = TranslateController()
        let combo = HotkeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey))
        XCTAssertTrue(controller.registerHotkey(combo), "setup: tổ hợp này phải còn trống")

        let model = makeModel(translate: controller)

        XCTAssertEqual(model.hotkey, combo)
        XCTAssertTrue(model.hotkeyIsRegistered)
    }

    /// Va chạm Carbon THẬT (cùng cách `TranslateControllerHotkeyTests` dựng):
    /// đăng ký trước tổ hợp rồi bảo model ghi đúng tổ hợp đó.
    func testRecordingAComboAnotherAppOwnsKeepsTheOldHotkeyAndSaysSo() {
        let taken = HotkeyCombo(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey))
        let occupier = HotkeyMonitor(keyCode: taken.keyCode, modifiers: taken.modifiers) {}
        defer { occupier.unregister() }
        XCTAssertTrue(occupier.register(), "setup: phải chiếm được tổ hợp trước")

        let controller = TranslateController()
        let model = makeModel(translate: controller)
        let before = model.hotkey

        model.recordHotkey(taken)

        XCTAssertEqual(model.hotkey, before, "tổ hợp bị chiếm không được thay thế tổ hợp đang dùng")
        XCTAssertTrue(model.status?.contains(taken.displayString) == true,
                      "phải nói RÕ tổ hợp nào bị chiếm, thấy: \(model.status ?? "nil")")
        XCTAssertEqual(model.hotkeyIsRegistered, controller.isHotkeyRegistered,
                       "cờ trên model phải bám controller, không phải một bản nhớ riêng")
    }

    /// Hotkey toàn cục không modifier nuốt phím đó ở MỌI app. `applyHotkey`
    /// đã chặn, nhưng người dùng phải được biết VÌ SAO chứ không phải nghe
    /// "app khác đang chiếm" — một câu sai.
    func testAComboWithoutModifiersIsRefusedWithTheRealReason() {
        let model = makeModel()

        model.recordHotkey(HotkeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: 0))

        XCTAssertEqual(model.hotkey, .default)
        XCTAssertTrue(model.status?.contains("bổ trợ") == true,
                      "phải nêu đúng lý do (thiếu phím bổ trợ), thấy: \(model.status ?? "nil")")
    }

    // MARK: - Đổi chỗ db (ràng buộc 2 và 3)

    private func newDir(_ name: String) throws -> URL {
        let dir = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testASuccessfulRelocationMovesThePathAndRecordsTheOverride() throws {
        let target = try newDir("new")
        let store = FakeStore()
        let model = makeModel(maintenance: store)

        model.relocateDatabase(to: target)

        XCTAssertEqual(model.dbDirectory.path, target.path)
        XCTAssertEqual(defaults.string(forKey: DatabaseLocation.overrideKey), target.path,
                       "override chỉ được ghi SAU khi file đã nằm ở đích và đọc được")
        XCTAssertFalse(model.needsRestart)
    }

    /// `.failed` = đã rollback sạch, db vẫn ở chỗ cũ, app tự chạy tiếp được.
    func testACleanFailureKeepsThePathAndNeverAsksForARestart() throws {
        let target = try newDir("new")
        let newDB = target.appendingPathComponent("ktranslate.db")
        let store = FakeStore()
        store.openSucceeds = { $0 != newDB }   // mở ở chỗ mới hỏng, mở lại chỗ cũ được
        let model = makeModel(maintenance: store)

        model.relocateDatabase(to: target)

        XCTAssertEqual(model.dbPath, dbPath)
        XCTAssertNil(defaults.string(forKey: DatabaseLocation.overrideKey))
        XCTAssertFalse(model.needsRestart, ".failed nghĩa là dữ liệu vẫn an toàn — đừng doạ người dùng")
    }

    /// 🔑 Ràng buộc 2. `.failedAndStoreClosed` = KHÔNG còn store nào mở; app
    /// không tự phục hồi được. Hai case phải ra hai thông điệp khác nhau,
    /// nếu không người dùng đọc "db vẫn ở chỗ cũ" rồi tra tiếp vào hư không.
    func testAStoreClosedFailureAsksForARestartAndReadsDifferently() throws {
        let target = try newDir("new")
        let cleanTarget = try newDir("new-clean")
        let cleanStore = FakeStore()
        cleanStore.openSucceeds = { $0 != cleanTarget.appendingPathComponent("ktranslate.db") }
        let cleanModel = makeModel(maintenance: cleanStore)
        cleanModel.relocateDatabase(to: cleanTarget)
        let cleanMessage = cleanModel.status

        let store = FakeStore()
        store.openSucceeds = { _ in false }   // cả mở mới lẫn mở lại cũ đều hỏng
        let model = makeModel(maintenance: store)

        model.relocateDatabase(to: target)

        XCTAssertTrue(model.needsRestart,
                      "không còn store nào mở — người dùng PHẢI được bảo khởi động lại")
        XCTAssertNotEqual(model.status, cleanMessage,
                          "hai mức nghiêm trọng khác nhau không được dùng chung một câu")
        XCTAssertTrue(model.status?.contains("mở lại KuroTools") == true,
                      "phải nói rõ việc cần làm, thấy: \(model.status ?? "nil")")
    }

    /// 🔑 Ràng buộc 3. `DataRelocation.relocate` KHÔNG có guard tái nhập: lần
    /// gọi thứ hai sẽ rollback và đóng đúng store mà lần đầu vừa mở. Dựng
    /// đúng cửa sổ đó bằng cách bắn lời gọi thứ hai từ trong `openStore`.
    func testARelocationStartedWhileAnotherIsInFlightIsRefused() throws {
        let target = try newDir("new")
        let second = try newDir("second")
        let store = FakeStore()
        let model = makeModel(maintenance: store)
        var reentered = 0
        store.onOpen = { [weak model] in
            guard reentered == 0 else { return }
            reentered += 1
            model?.relocateDatabase(to: second)
        }

        model.relocateDatabase(to: target)

        XCTAssertEqual(reentered, 1, "setup: lời gọi lồng nhau phải thật sự đã xảy ra")
        XCTAssertEqual(store.calls.filter { $0 == "close" }.count, 1,
                       "lời gọi thứ hai phải bị chặn TRƯỚC khi nó đóng store lần đầu vừa mở")
        XCTAssertEqual(model.dbDirectory.path, target.path)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: second.appendingPathComponent("ktranslate.db").path),
            "không được có bản copy nào ở thư mục của lời gọi bị chặn")
    }

    func testACloudSyncedDestinationIsRefusedByName() throws {
        let target = try newDir("new")
        let store = FakeStore()
        let model = makeModel(maintenance: store)

        model.relocateDatabase(to: target, verdict: { _ in .cloudSynced("Dropbox") })

        XCTAssertTrue(model.status?.contains("Dropbox") == true,
                      "phải gọi tên dịch vụ để người dùng biết đường mà tránh, thấy: \(model.status ?? "nil")")
        XCTAssertEqual(store.calls, [], "bị từ chối từ vòng kiểm trước — không được đụng tới store")
        XCTAssertEqual(model.dbPath, dbPath)
    }

    // MARK: - Xoá dữ liệu (ràng buộc 6)

    /// 🔑 Ràng buộc 6. `.everything` xoá cả domain `UserDefaults`, tức xoá
    /// luôn override vị trí db, nên `DataReset` mở lại ở `defaultDBPath`.
    /// Compiler không bắt được việc model quên đi theo — nó vẫn hiện thư mục
    /// tuỳ chỉnh cũ trong khi db thật đã nằm ở chỗ mặc định.
    func testResettingEverythingMovesTheShownPathBackToTheDefault() {
        let backend = StubBackend()
        let model = makeModel(backend: backend)
        defaults.set(dbPath.deletingLastPathComponent().path, forKey: DatabaseLocation.overrideKey)

        model.reset(.everything)

        XCTAssertEqual(backend.openedPaths, [defaultDBPath], "kiểm chéo: store đã mở lại ở default")
        XCTAssertEqual(model.dbPath, defaultDBPath,
                       "UI phải chỉ vào chỗ db THẬT SỰ đang nằm sau khi xoá sạch")
        XCTAssertEqual(model.dbDirectory.path, defaultDBPath.deletingLastPathComponent().path)
        XCTAssertNil(defaults.string(forKey: DatabaseLocation.overrideKey),
                     "override đã bị xoá cùng domain — model không được ghi lại nó")
    }

    func testAFullResetThatCannotReopenTheStoreAsksForARestart() {
        let backend = StubBackend()
        backend.openStoreSucceeds = false
        let model = makeModel(backend: backend)

        model.reset(.everything)

        XCTAssertTrue(model.needsRestart, "không mở lại được store thì app không còn db nào")
        XCTAssertEqual(model.dbPath, dbPath, "đừng khẳng định db nằm ở chỗ mà nó không mở được")
    }

    func testAFailedHistoryClearIsReportedButNeedsNoRestart() {
        let backend = StubBackend()
        backend.clearHistorySucceeds = false
        let model = makeModel(backend: backend)

        model.reset(.history)

        XCTAssertTrue(model.status?.contains("Không xoá được") == true,
                      "nuốt lỗi ở đây nghĩa là UI báo đã xoá trong khi dữ liệu còn nguyên, thấy: \(model.status ?? "nil")")
        XCTAssertFalse(model.needsRestart, "xoá lịch sử hỏng không làm mất store")
    }

    func testClearingHistoryLeavesSavedWordsAlone() {
        let backend = StubBackend()
        let model = makeModel(backend: backend)

        model.reset(.history)

        XCTAssertEqual(backend.calls, ["clearHistory"])
    }

    // MARK: - Xác nhận xoá sạch phải gõ đúng chữ

    func testOnlyTheExactPhraseUnlocksTheFullReset() {
        XCTAssertTrue(ResetConfirmation.canProceed(scope: .history, typed: ""))
        XCTAssertTrue(ResetConfirmation.canProceed(scope: .savedWords, typed: ""))
        XCTAssertFalse(ResetConfirmation.canProceed(scope: .everything, typed: ""))
        XCTAssertFalse(ResetConfirmation.canProceed(scope: .everything, typed: "XOA"),
                       "thiếu dấu là một chữ KHÁC — đây là cổng cuối trước khi mất hết dữ liệu")
        XCTAssertFalse(ResetConfirmation.canProceed(scope: .everything, typed: "xoá"))
        XCTAssertTrue(ResetConfirmation.canProceed(scope: .everything, typed: "XOÁ"))
        XCTAssertTrue(ResetConfirmation.canProceed(scope: .everything, typed: "  XOÁ \n"),
                      "khoảng trắng thừa khi dán không nên bắt người dùng gõ lại")
    }

    // MARK: - Vitals

    func testApplyingVitalsSettingsGoesThroughTheController() {
        let vitals = VitalsController(defaults: defaults)
        let model = SettingsModel(
            translate: TranslateController(), vitals: vitals, backend: StubBackend(),
            loginItem: StubLoginItem(), maintenance: FakeStore(), dbPath: dbPath,
            defaultDBPath: defaultDBPath, defaults: defaults, bundleID: suiteName)

        var next = model.vitalsSettings()
        next.thresholdC = 88
        next.showRAM = false
        model.applyVitals(next)

        XCTAssertEqual(vitals.currentSettings.thresholdC, 88)
        XCTAssertFalse(vitals.currentSettings.showRAM)
        XCTAssertEqual(model.vitalsSettings().thresholdC, 88)
        vitals.timer?.invalidate()
    }
}
