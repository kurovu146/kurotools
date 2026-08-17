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
    var journal: CallJournal?

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
    func closeStore() -> Bool {
        calls.append("close")
        journal?.entries.append("close")
        return true
    }
    func openStore(at dbPath: URL) -> Bool {
        calls.append("open")
        journal?.entries.append("open")
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
    /// Nhật ký DÙNG CHUNG với `SpyTranslate` — thứ tự giữa hai đối tượng khác
    /// nhau (đóng popup rồi mới đóng store) không đo được từ hai mảng rời.
    var journal: CallJournal?

    func closeStore() -> Bool { record("close"); return closeSucceeds }
    func openStore(at dbPath: URL) -> Bool {
        record("open")
        openPaths.append(dbPath)
        onOpen?()
        return openSucceeds(dbPath)
    }
    func canRead() -> Bool { record("read"); return readable }

    private func record(_ entry: String) {
        calls.append(entry)
        journal?.entries.append(entry)
    }
}

private final class CallJournal {
    var entries: [String] = []
}

/// `TranslateController` giả — chỉ để quan sát THỨ TỰ (`hidePopup` trước khi
/// store bị đóng) và việc `applyHotkey` có được gọi hay không. Test hotkey vẫn
/// dùng controller THẬT.
@MainActor
private final class SpyTranslate: TranslateControlling {
    var currentHotkey: HotkeyCombo = HotkeyCombo(
        keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey))
    var isHotkeyRegistered = true
    var applied: [HotkeyCombo] = []
    var applyResult = true
    var journal: CallJournal?

    func applyHotkey(_ combo: HotkeyCombo) -> Bool {
        applied.append(combo)
        journal?.entries.append("applyHotkey")
        if applyResult { currentHotkey = combo }
        isHotkeyRegistered = applyResult
        return applyResult
    }

    func hidePopup() { journal?.entries.append("hidePopup") }
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
        (defaults, suiteName) = PreferencesSandbox.make("settings")
    }

    override func tearDownWithError() throws {
        PreferencesSandbox.destroy(suiteName)
        try? FileManager.default.removeItem(at: tmp)
    }

    /// `translate` là `nil` mặc định chứ không phải `TranslateController()`:
    /// biểu thức mặc định của tham số chạy ở ngữ cảnh nonisolated, mà
    /// `TranslateController.init` là `@MainActor`.
    private func makeModel(
        loginItem: LoginItemControlling = StubLoginItem(),
        backend: TranslateBackend = StubBackend(),
        maintenance: StoreMaintaining? = nil,
        translate: TranslateControlling? = nil,
        vitals: VitalsController? = nil
    ) -> SettingsModel {
        SettingsModel(
            translate: translate ?? TranslateController(),
            vitals: vitals ?? VitalsController(defaults: defaults),
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
        let model = SettingsModel.forTesting(loginItem: login, defaults: defaults, bundleID: suiteName)

        model.setRunAtLogin(true)

        XCTAssertFalse(model.runAtLogin, "công tắc phải bám trạng thái THẬT của hệ thống")
        XCTAssertNotNil(model.status, "thất bại phải nói ra, không im lặng")
    }

    func testASuccessfulLoginItemToggleSticks() {
        let login = StubLoginItem()
        let model = SettingsModel.forTesting(loginItem: login, defaults: defaults, bundleID: suiteName)
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
        let model = SettingsModel.forTesting(loginItem: login, defaults: defaults, bundleID: suiteName)

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
        let model = SettingsModel.forTesting(loginItem: login, defaults: defaults, bundleID: suiteName)
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

        var next = model.vitalsSettings
        next.thresholdC = 88
        next.showRAM = false
        model.applyVitals(next)

        XCTAssertEqual(vitals.currentSettings.thresholdC, 88)
        XCTAssertFalse(vitals.currentSettings.showRAM)
        XCTAssertEqual(model.vitalsSettings.thresholdC, 88,
                       "tab đọc bản `@Published` này — không cập nhật nó thì mọi control trong tab đứng hình")
        vitals.timer?.invalidate()
    }

    // MARK: - Fix round 1

    /// 🔑 Spec §6 mức 3 liệt kê NĂM việc; trước bản vá code chỉ làm bốn. Không
    /// đưa hotkey về mặc định + đăng ký lại ngay thì cửa sổ hiện tổ hợp cũ
    /// trong khi preference đã bị xoá, và tới lần khởi động sau nó âm thầm
    /// thành ⇧⌘D — có thể đang bị app khác giữ, không ai báo gì.
    func testAFullResetReturnsTheHotkeyToTheDefaultAndRegistersItAgain() {
        let spy = SpyTranslate()
        let model = makeModel(translate: spy)
        XCTAssertNotEqual(model.hotkey, .default, "setup: đang dùng một tổ hợp tuỳ chỉnh")

        model.reset(.everything)

        XCTAssertEqual(spy.applied, [.default],
                       "phải ĐĂNG KÝ LẠI ngay, không chỉ xoá preference rồi đợi lần khởi động sau")
        XCTAssertEqual(model.hotkey, .default)
        XCTAssertTrue(model.hotkeyIsRegistered)
    }

    /// Cùng đường trên, nhánh tổ hợp mặc định đang bị app khác giữ: người dùng
    /// phải được báo, không được để UI nói dối là phím tắt đang chạy.
    func testAFullResetSaysSoWhenTheDefaultHotkeyIsAlreadyTaken() {
        let spy = SpyTranslate()
        spy.applyResult = false
        let model = makeModel(translate: spy)

        model.reset(.everything)

        XCTAssertFalse(model.hotkeyIsRegistered)
        XCTAssertTrue(model.status?.contains("đang bị app khác giữ") == true,
                      "thấy: \(model.status ?? "nil")")
    }

    /// 🔑 `removePersistentDomain` dọn kho preference, nhưng `VitalsController`
    /// giữ một bản sao nạp từ lúc khởi tạo — lần `apply()` kế tiếp ghi lại đủ
    /// SÁU khoá cũ xuống đĩa. Người dùng xoá sạch, nhích một control, và ngưỡng
    /// cũ sống lại: kho bị đầu độc lại chứ không chỉ là bản sao cũ trong bộ nhớ.
    func testWipedVitalsPreferencesCannotBeResurrectedByALaterSave() {
        let vitals = VitalsController(defaults: defaults)
        let model = makeModel(vitals: vitals)
        var custom = model.vitalsSettings
        custom.thresholdC = 88
        custom.showRAM = false
        model.applyVitals(custom)
        XCTAssertEqual(Vitals.Settings.load(defaults: defaults).thresholdC, 88, "setup")

        model.reset(.everything)

        // Người dùng nhích một control bất kỳ trong tab Vitals sau khi xoá sạch.
        vitals.apply(vitals.currentSettings)

        let onDisk = Vitals.Settings.load(defaults: defaults)
        XCTAssertEqual(onDisk.thresholdC, 95, "ngưỡng cũ không được sống lại")
        XCTAssertTrue(onDisk.showRAM, "cờ hiển thị cũ không được sống lại")
        vitals.timer?.invalidate()
    }

    /// §3.4: chặn ổ mạng là bảo vệ chính của cả tính năng — SQLite hỏng thật
    /// trên NAS/SMB vì file locking không đáng tin.
    func testANetworkVolumeDestinationIsRefusedWithoutTouchingTheStore() throws {
        let target = try newDir("nas")
        let store = FakeStore()
        let model = makeModel(maintenance: store)

        model.relocateDatabase(to: target, verdict: { _ in .notLocalVolume })

        XCTAssertTrue(model.status?.contains("ổ local") == true,
                      "phải nói rõ vì sao bị từ chối, thấy: \(model.status ?? "nil")")
        XCTAssertEqual(store.calls, [], "bị từ chối ở vòng kiểm trước — không được đụng tới store")
        XCTAssertEqual(model.dbPath, dbPath)
    }

    /// Banner đỏ "hãy khởi động lại" phải BIẾN MẤT khi app đã tự phục hồi —
    /// một lần đổi chỗ thành công sau đó chứng minh có store đang mở, và để
    /// banner nằm lại là bảo người dùng thoát một app đang chạy tốt.
    func testARecoveredStoreClearsTheRestartBanner() throws {
        let broken = try newDir("broken")
        let good = try newDir("good")
        let store = FakeStore()
        store.openSucceeds = { _ in false }
        let model = makeModel(maintenance: store)

        model.relocateDatabase(to: broken)
        XCTAssertTrue(model.needsRestart, "setup: phải rơi vào .failedAndStoreClosed")

        store.openSucceeds = { _ in true }
        model.relocateDatabase(to: good)

        XCTAssertEqual(model.dbDirectory.path, good.path)
        XCTAssertFalse(model.needsRestart, "store đã mở lại được — đừng bắt người dùng thoát app")
    }

    /// Spec §5 bước 2: đóng popup TRƯỚC `kt_close()`. Popup đang hiện là nơi
    /// duy nhất còn có thể sinh một `lookup` mới ngay lúc store sắp đóng.
    func testTheLookupPopupIsClosedBeforeTheStoreIsClosedWhenRelocating() throws {
        let target = try newDir("new")
        let journal = CallJournal()
        let store = FakeStore()
        store.journal = journal
        let spy = SpyTranslate()
        spy.journal = journal
        let model = makeModel(maintenance: store, translate: spy)

        model.relocateDatabase(to: target)

        let hid = try XCTUnwrap(journal.entries.firstIndex(of: "hidePopup"))
        let closed = try XCTUnwrap(journal.entries.firstIndex(of: "close"))
        XCTAssertLessThan(hid, closed, "thứ tự thật: \(journal.entries)")
    }

    func testTheLookupPopupIsClosedBeforeTheStoreIsClosedWhenWipingEverything() {
        let journal = CallJournal()
        let backend = StubBackend()
        backend.journal = journal
        let spy = SpyTranslate()
        spy.journal = journal
        let model = makeModel(backend: backend, translate: spy)

        model.reset(.everything)

        XCTAssertEqual(journal.entries.first, "hidePopup", "thứ tự thật: \(journal.entries)")
    }

    /// Cửa sổ mở lần thứ hai phải đọc lại cặp ngôn ngữ: người dùng có thể vừa
    /// đổi nó ngay trong popup tra từ, hoặc db vừa bị đổi chỗ/xoá sạch.
    func testReopeningTheWindowRereadsTheLanguageConfiguration() {
        let backend = StubBackend()
        backend.config = LangConfig(source: nil, target: "vi", other: "en")
        let model = makeModel(backend: backend)

        model.refreshFromSystem()
        XCTAssertEqual(model.langConfig?.target, "vi")
        XCTAssertEqual(model.languages, ["en", "vi"])

        backend.config = LangConfig(source: nil, target: "ja", other: "en")
        model.refreshFromSystem()

        XCTAssertEqual(model.langConfig?.target, "ja",
                       "mở lại cửa sổ mà vẫn hiện bản nạp lần đầu là đúng bug .onAppear chỉ chạy một lần")
    }
}
