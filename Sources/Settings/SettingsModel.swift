import Foundation
import SwiftUI
import Translate
import Vitals

/// Nối `TranslateBackend` (Task 6) sang `StoreMaintaining` (Task 5).
/// `KTranslateBridge` có `closeStore`/`openStore` nhưng KHÔNG có `canRead()`,
/// nên không tự conform được — và adapter phải nằm ở đây, nơi duy nhất import
/// cả hai phía.
///
/// `canRead()` gồm hai phần, vì một mình phần đầu không đủ:
/// 1. `langConfig() != nil` — một truy vấn đọc THẬT xuống SQLite. `kt_init`
///    tạo file rỗng cho đường dẫn sai mà vẫn báo thành công, nên "mở được"
///    không chứng minh được gì.
/// 2. Tiến trình có đang giữ file ở đường dẫn vừa mở không (`OpenFileProbe`).
///    Phần 1 CHỈ chứng minh store còn sống: nếu `closeStore()` báo thành công
///    trong khi thực ra chưa đóng, `kt_init` thành no-op thành công và phép
///    đọc trúng db CŨ — "qua" y hệt, rồi `relocate` báo `.moved` trong khi
///    mọi lần ghi sau đó rơi vào file sắp bị đổi tên. Đây là giới hạn mà
///    review Task 5 ghi lại và giao sang task này.
///
/// Vẫn còn một khe không đóng được từ Swift: phép kiểm chứng minh **tiến
/// trình** giữ file, không chứng minh **`Store` của Rust** là thứ giữ nó.
/// Muốn chặt hơn phải có FFI trả về đường dẫn store đang mở.
public final class BackendStoreMaintenance: StoreMaintaining {
    private let backend: TranslateBackend
    /// Đường dẫn của lần `openStore` THÀNH CÔNG gần nhất — thứ mà `canRead()`
    /// đối chiếu. `nil` khi chưa mở gì qua adapter này.
    private var lastOpened: URL?

    public init(backend: TranslateBackend) {
        self.backend = backend
    }

    public func closeStore() -> Bool { backend.closeStore() }

    public func openStore(at dbPath: URL) -> Bool {
        let opened = backend.openStore(at: dbPath)
        // Chỉ nhớ khi mở THÀNH CÔNG: mở hỏng thì việc tiếp theo là rollback,
        // không phải đi kiểm một file chưa bao giờ được mở.
        lastOpened = opened ? dbPath : nil
        return opened
    }

    public func canRead() -> Bool {
        guard backend.langConfig() != nil else { return false }
        guard let lastOpened else { return true }
        // `nil` = libproc không trả lời được. Không kết luận gì từ một phép
        // đo hỏng: hạ nó thành "không đọc được" sẽ biến một lần đổi chỗ db
        // hoàn toàn hợp lệ thành rollback.
        return OpenFileProbe.processHasOpen(lastOpened) ?? true
    }
}

/// Trạng thái của cửa sổ Settings và mọi thao tác nó gây ra. Ba tab chỉ đọc và
/// gọi vào đây; không tab nào tự chạm `UserDefaults`, `DataReset` hay
/// `DataRelocation`.
@MainActor
public final class SettingsModel: ObservableObject {
    private let translate: TranslateController
    private let vitals: VitalsController
    private let backend: TranslateBackend
    private let loginItem: LoginItemControlling
    private let maintenance: StoreMaintaining
    private let defaults: UserDefaults
    private let bundleID: String
    /// Chỗ db nằm khi không có override — `DataReset.perform(.everything, …)`
    /// mở lại store ở ĐÂY, không phải ở `dbPath`.
    private let defaultDBPath: URL

    /// Tổ hợp phím đang được cấu hình. `private(set)`: mọi thay đổi phải đi
    /// qua `recordHotkey` để kết quả đăng ký thật được ghi nhận.
    @Published public private(set) var hotkey: HotkeyCombo
    /// Tổ hợp trên có thật sự đang sống với hệ thống không. Tách hẳn khỏi
    /// `hotkey` vì "anh chọn ⇧⌘D" và "⇧⌘D là của anh" là hai chuyện khác
    /// nhau — ca thứ hai sai ngay từ lần khởi động ĐẦU TIÊN nếu app khác đã
    /// giữ tổ hợp đó, không cần người dùng làm gì sai cả.
    @Published public private(set) var hotkeyIsRegistered: Bool
    /// Công tắc "chạy khi đăng nhập" — `true` cho cả `.on` lẫn
    /// `.requiresApproval`: đã đăng ký xong rồi, chỉ còn chờ duyệt. Hạ nó về
    /// `false` ở trạng thái chờ duyệt làm công tắc tự bật rồi tự tắt.
    @Published public private(set) var runAtLogin: Bool
    /// Trạng thái đầy đủ, để UI giải thích được ca `.requiresApproval`.
    @Published public private(set) var loginItemState: LoginItemState
    /// Dòng phản hồi dưới cửa sổ. `private(set)`: chỉ những thao tác ở đây mới
    /// được viết vào nó.
    @Published public private(set) var status: String?
    @Published public private(set) var dbPath: URL
    /// Khoá control đổi chỗ trong lúc một lần đổi chỗ đang chạy —
    /// `DataRelocation.relocate` KHÔNG có guard tái nhập, và rollback của lời
    /// gọi thứ hai sẽ đóng đúng store mà lời gọi đầu vừa mở.
    @Published public private(set) var isRelocating = false
    /// App đang KHÔNG có store nào mở và không tự phục hồi được — chỉ đường
    /// `.failedAndStoreClosed` và `.everything` mở lại hỏng mới bật cờ này.
    @Published public private(set) var needsRestart = false

    public var dbDirectory: URL { dbPath.deletingLastPathComponent() }

    /// `maintenance` mặc định là adapter bọc chính `backend`; test tiêm store
    /// giả để dựng đủ bốn nhánh `RelocationOutcome`. `defaults`/`bundleID`
    /// cũng là seam — `DataReset.perform(.everything, …)` xoá cả một
    /// persistent domain, và một test lỡ chạy vào domain thật sẽ xoá sạch
    /// preference của máy.
    public init(
        translate: TranslateController,
        vitals: VitalsController,
        backend: TranslateBackend,
        loginItem: LoginItemControlling,
        maintenance: StoreMaintaining? = nil,
        dbPath: URL,
        defaultDBPath: URL = DatabaseMigration.defaultDatabasePath(
            appSupport: DatabaseMigration.defaultAppSupport()),
        defaults: UserDefaults = .standard,
        bundleID: String = DatabaseMigration.currentBundleID
    ) {
        self.translate = translate
        self.vitals = vitals
        self.backend = backend
        self.loginItem = loginItem
        self.maintenance = maintenance ?? BackendStoreMaintenance(backend: backend)
        self.dbPath = dbPath
        self.defaultDBPath = defaultDBPath
        self.defaults = defaults
        self.bundleID = bundleID
        hotkey = translate.currentHotkey
        hotkeyIsRegistered = translate.isHotkeyRegistered
        loginItemState = loginItem.state
        runAtLogin = loginItem.state != .off
    }

    /// Đọc lại những thứ hệ thống có thể đã đổi sau lưng app: login item bị
    /// tắt trong System Settings, hay quyền duyệt vừa được cấp. Gọi mỗi lần
    /// cửa sổ hiện ra — nhớ trạng thái cũ là cách sinh ra một công tắc "bật"
    /// trong khi launchd không biết gì.
    public func refreshFromSystem() {
        readLoginItemState()
        hotkey = translate.currentHotkey
        hotkeyIsRegistered = translate.isHotkeyRegistered
    }

    // MARK: - Phím tắt

    public func recordHotkey(_ combo: HotkeyCombo) {
        guard combo.isValid else {
            // `applyHotkey` cũng từ chối ca này, nhưng nó trả về đúng một
            // `false` như khi bị app khác chiếm — nói "app khác đang chiếm"
            // ở đây là một câu SAI.
            status = "Phím tắt phải có ít nhất một phím bổ trợ (⌘/⌥/⌃/⇧)."
            return
        }
        if translate.applyHotkey(combo) {
            hotkey = combo
            status = "Phím tắt: \(combo.displayString)"
        } else {
            hotkey = translate.currentHotkey
            status = "Tổ hợp \(combo.displayString) đang bị app khác chiếm — giữ nguyên \(hotkey.displayString)."
        }
        hotkeyIsRegistered = translate.isHotkeyRegistered
    }

    // MARK: - Chạy khi đăng nhập

    /// Công tắc bám trạng thái THẬT: đọc lại từ `loginItem.state` sau mỗi lần
    /// đặt. Nhớ ý định của UI thay vì hỏi hệ thống là cách sinh ra một công
    /// tắc "bật" trong khi launchd không biết gì.
    public func setRunAtLogin(_ on: Bool) {
        do {
            try loginItem.setEnabled(on)
            readLoginItemState()
            switch loginItemState {
            case .on:
                status = "Đã bật chạy khi đăng nhập."
            case .requiresApproval:
                status = "Đã đăng ký. Còn một bước: duyệt KuroTools trong System Settings ▸ General ▸ Login Items."
            case .off:
                // `register()` không throw mà hệ thống vẫn báo chưa đăng ký —
                // im lặng ở đây để lại một công tắc tự tắt không lời giải thích.
                status = on ? "macOS chưa nhận đăng ký — thử lại hoặc kiểm tra Login Items." : "Đã tắt chạy khi đăng nhập."
            }
        } catch {
            readLoginItemState()
            status = "Không đổi được: \(error.localizedDescription)"
        }
    }

    private func readLoginItemState() {
        loginItemState = loginItem.state
        runAtLogin = loginItemState != .off
    }

    // MARK: - Đổi chỗ db

    /// `verdict` là seam của `DataRelocation.relocate` — test dựng ca ổ mạng /
    /// thư mục cloud mà không cần một ổ mạng thật.
    public func relocateDatabase(
        to directory: URL,
        verdict: (URL) -> LocationVerdict = LocalVolumeCheck.verdictOnDisk
    ) {
        // `relocate` không có guard tái nhập: lời gọi thứ hai đóng store, thấy
        // đích đã có db, rồi rollback — và cái rollback đó đóng đúng store mà
        // lời gọi đầu vừa mở ở chỗ mới. UI cũng khoá nút, nhưng cổng thật phải
        // nằm ở đây, nơi biết chắc một lần đổi chỗ đang chạy.
        guard !isRelocating else {
            status = "Đang chuyển db — chờ xong đã."
            return
        }
        isRelocating = true
        defer { isRelocating = false }

        switch DataRelocation.relocate(
            currentDB: dbPath, toDirectory: directory, store: maintenance, verdict: verdict
        ) {
        case .moved(let to, let oldRenamedTo):
            // Ghi override CHỈ ở nhánh này: `DatabaseLocation.resolve` chỉ
            // kiểm sự tồn tại của file, nên một override trỏ vào thư mục chưa
            // có db sẽ âm thầm rơi về mặc định (ràng buộc mang sang từ Task 4).
            DatabaseLocation.setOverride(to.deletingLastPathComponent(), defaults: defaults)
            dbPath = to
            status = "Đã chuyển. Bản cũ còn ở \(oldRenamedTo.path) — xoá khi anh yên tâm."
        case .rejected(.notLocalVolume):
            status = "Chỉ đặt được trên ổ local: SQLite hỏng trên ổ mạng."
        case .rejected(.cloudSynced(let service)):
            status = "\(service) đồng bộ file nền và sẽ làm hỏng db. Chọn thư mục khác."
        case .rejected(.ok):
            // Không thể xảy ra — `relocate` chỉ trả `.rejected` khi verdict
            // KHÁC `.ok`. Liệt kê tay để không có `default:` nào nuốt mất một
            // case mới thêm về sau.
            status = nil
        case .failed(let reason):
            status = "Không chuyển được: \(reason) Db vẫn ở chỗ cũ."
        case .failedAndStoreClosed(let reason):
            // KHÁC HẲN `.failed`: rollback không mở lại được db cũ, hiện không
            // có store nào mở ở đâu cả. App không tự phục hồi được (không còn
            // biết trạng thái thật của driver Rust nữa), nên câu duy nhất đúng
            // là bảo người dùng khởi động lại.
            needsRestart = true
            status = "\(reason) Hãy thoát và mở lại KuroTools — tra cứu bây giờ sẽ không lưu được gì."
        }
    }

    // MARK: - Xoá dữ liệu

    public func reset(_ scope: ResetScope) {
        let succeeded = DataReset(backend: backend, defaults: defaults)
            .perform(scope, dbPath: dbPath, defaultDBPath: defaultDBPath, bundleID: bundleID)

        switch scope {
        case .history:
            status = succeeded ? "Đã xoá lịch sử tra." : "Không xoá được lịch sử — db chưa đổi gì."
        case .savedWords:
            status = succeeded ? "Đã xoá từ đã lưu." : "Không xoá được từ đã lưu — db chưa đổi gì."
        case .everything:
            guard succeeded else {
                // `perform` chỉ trả `false` ở mức này khi mở lại store thất
                // bại — file đã bị xoá, không còn db nào đang mở.
                needsRestart = true
                status = "Đã xoá sạch nhưng không mở lại được db. Hãy thoát và mở lại KuroTools."
                return
            }
            // 🔑 `perform` mở lại store ở `defaultDBPath` (nó vừa xoá cả
            // domain `UserDefaults`, tức xoá luôn override vị trí db), nhưng
            // nó vẫn trả `Bool` — không có gì buộc chỗ này đi theo. Quên dòng
            // dưới thì UI chỉ vào thư mục tuỳ chỉnh cũ trong khi db thật đã
            // nằm ở chỗ mặc định.
            dbPath = defaultDBPath
            status = "Đã xoá sạch. Db mới nằm ở \(dbDirectory.path). Cấu hình khác trở lại mặc định ở lần khởi động sau."
        }
    }

    // MARK: - Vitals

    public func vitalsSettings() -> Vitals.Settings { vitals.currentSettings }

    /// Một đường DUY NHẤT vào preference của Vitals: `VitalsController.apply`
    /// còn phải đẩy ngưỡng xuống `FanController` và đặt lại nhịp timer, nên
    /// ghi thẳng `UserDefaults` từ tab là cách làm UI báo đã đổi trong khi hệ
    /// thống chạy theo giá trị cũ.
    public func applyVitals(_ settings: Vitals.Settings) {
        vitals.apply(settings)
        // `Vitals.Settings` sống trong controller chứ không phải một
        // `@Published` ở đây; chính phép gán `status` này là thứ phát
        // `objectWillChange` để tab đọc lại giá trị vừa lưu.
        status = "Đã lưu cài đặt theo dõi."
    }

    // MARK: - Ngôn ngữ (tab Dịch đọc/ghi qua backend)

    public func languages() -> [String] { backend.languages() }
    public func recentLanguages() -> [String] { backend.recentLanguages() }
    public func langConfig() -> LangConfig? { backend.langConfig() }

    /// Trả về thứ backend THỰC SỰ lưu, không phải thứ vừa chọn: `LangConfig::new`
    /// phía Rust sửa va chạm (đích trùng nguồn, v.v.), nên hai giá trị có thể
    /// khác nhau và tab phải hiển thị lại giá trị trả về.
    public func setLangConfig(source: String?, target: String, other: String) -> LangConfig? {
        let saved = backend.setLangConfig(source: source, target: target, other: other)
        status = saved == nil ? "Không lưu được lựa chọn ngôn ngữ." : nil
        return saved
    }
}

#if DEBUG
/// Backend trơ cho test: không FFI, không store. Chỉ tồn tại trong bản DEBUG.
private final class InertBackend: TranslateBackend {
    func capture() -> CaptureOutcome { .empty }
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void) {}
    func languages() -> [String] { [] }
    func recentLanguages() -> [String] { [] }
    func langConfig() -> LangConfig? { nil }
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig? { nil }
    func hasAccessibility() -> Bool { false }
    func requestAccessibility() -> Bool { false }
    func ttsAvailable() -> Bool { false }
    func speak(_ text: String) {}
    func isSaved(_ word: String) -> Bool { false }
    func setSaved(_ word: String, saved: Bool) -> Bool { false }
    // Bốn hàm vòng đời store PHẢI khai báo tay ở đây: default của chúng nằm
    // trong `extension TranslateBackend` với mức truy cập internal, nên nó
    // không thoả được một protocol requirement `public` khi nhìn từ module
    // KHÁC (chỉ test target — dùng `@testable` — mới thấy). Đã báo lại cho
    // team-lead như một khe access-level của Task 6.
    func closeStore() -> Bool { false }
    func openStore(at dbPath: URL) -> Bool { false }
    func clearHistory() -> Bool { false }
    func clearSavedWords() -> Bool { false }
}

extension SettingsModel {
    /// Dựng model cho test mà không đụng gì THẬT: db ở thư mục tạm,
    /// `UserDefaults` là một suite dùng một lần, backend trơ.
    /// `TranslateController()` chưa gọi `start()` nên không mở store lẫn đăng
    /// ký hotkey nào.
    static func forTesting(
        loginItem: LoginItemControlling,
        suiteName: String = "kurotools.settings.forTesting.\(UUID().uuidString)"
    ) -> SettingsModel {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: suiteName)!
        return SettingsModel(
            translate: TranslateController(),
            vitals: VitalsController(defaults: defaults),
            backend: InertBackend(),
            loginItem: loginItem,
            dbPath: tmp.appendingPathComponent(DatabaseMigration.databaseName),
            defaultDBPath: tmp.appendingPathComponent(DatabaseMigration.databaseName),
            defaults: defaults,
            bundleID: suiteName)
    }
}
#endif
