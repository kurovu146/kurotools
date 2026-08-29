import Foundation
import SwiftUI
import Translate
import Vitals
import Wallpaper

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

/// Đúng những gì Settings cần từ `TranslateController`. `TranslateController`
/// là `final class` bọc thẳng Carbon + `NSPanel`, không có chỗ nhét test double
/// nào khác — mà thứ tự "đóng popup TRƯỚC khi đóng store" (spec §5 bước 2) chỉ
/// quan sát được nếu có thể ghi lại lời gọi.
///
/// Test hotkey vẫn dùng `TranslateController` THẬT (va chạm Carbon thật là
/// phép đo tốt hơn hẳn một cờ Bool); protocol này chỉ mở thêm đường cho những
/// test cần quan sát thứ tự.
@MainActor
public protocol TranslateControlling: AnyObject {
    var currentHotkey: HotkeyCombo { get }
    var isHotkeyRegistered: Bool { get }
    @discardableResult func applyHotkey(_ combo: HotkeyCombo) -> Bool
    func hidePopup()
}

extension TranslateController: TranslateControlling {}

/// Trạng thái copy video sang container của screensaver. Tách khỏi `status`
/// (chuỗi hiển thị) vì UI cần phân biệt "đang chạy" với "xong" — copy một video
/// vài trăm MB không tức thời.
public enum SaverSyncStatus: Equatable {
    case idle
    case syncing
    case synced
    case failed(String)
}

/// Trạng thái của cửa sổ Settings và mọi thao tác nó gây ra. Ba tab chỉ đọc và
/// gọi vào đây; không tab nào tự chạm `UserDefaults`, `DataReset` hay
/// `DataRelocation`.
@MainActor
public final class SettingsModel: ObservableObject {
    private let translate: TranslateControlling
    private let vitals: VitalsController
    private let backend: TranslateBackend
    private let loginItem: LoginItemControlling
    private let maintenance: StoreMaintaining
    private let wallpaper: WallpaperControlling
    private let saverInstaller: SaverVideoInstalling
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
    /// Được XOÁ ở mọi đường kết thúc với một store chắc chắn đang mở: một
    /// banner "hãy khởi động lại" nằm lì sau khi app đã tự phục hồi là một lời
    /// nói dối theo chiều ngược lại.
    @Published public private(set) var needsRestart = false

    /// Bản sao cấu hình Vitals, `@Published` một cách CÓ CHỦ Ý.
    /// `VitalsController.currentSettings` không phát tín hiệu gì, nên nếu tab
    /// đọc thẳng từ đó thì nó chỉ vẽ lại nhờ một `status` tình cờ được gán —
    /// xoá đúng dòng gán ấy là mọi control trong tab đứng hình mà cả bộ test
    /// vẫn xanh. Luôn được gán bằng giá trị ĐỌC LẠI từ controller, không phải
    /// giá trị vừa truyền vào, nên không có bản sao nào trôi đi được.
    @Published public private(set) var vitalsSettings: Vitals.Settings
    /// Ba thứ dưới đây đọc qua FFI nên KHÔNG đọc trong `body`. Nạp lại trong
    /// `refreshFromSystem()` (mỗi lần cửa sổ hiện) thay vì một lần trong
    /// `onAppear` của tab: db có thể vừa bị đổi chỗ hoặc xoá sạch giữa hai lần
    /// mở cửa sổ.
    @Published public private(set) var languages: [String] = []
    @Published public private(set) var recentLanguages: [String] = []
    @Published public private(set) var langConfig: LangConfig?

    /// Bản sao trạng thái wallpaper, đọc từ `WallpaperControlling` — controller
    /// (cửa sổ + AVPlayer thật) không được phép sống trong test.
    @Published public private(set) var wallpaperEnabled: Bool
    @Published public private(set) var wallpaperVideoURL: URL?
    @Published public private(set) var saverSyncStatus: SaverSyncStatus = .idle

    public var dbDirectory: URL { dbPath.deletingLastPathComponent() }

    /// `maintenance` mặc định là adapter bọc chính `backend`; test tiêm store
    /// giả để dựng đủ bốn nhánh `RelocationOutcome`. `defaults`/`bundleID`
    /// cũng là seam — `DataReset.perform(.everything, …)` xoá cả một
    /// persistent domain, và một test lỡ chạy vào domain thật sẽ xoá sạch
    /// preference của máy.
    public init(
        translate: TranslateControlling,
        vitals: VitalsController,
        backend: TranslateBackend,
        loginItem: LoginItemControlling,
        maintenance: StoreMaintaining? = nil,
        wallpaper: WallpaperControlling? = nil,
        saverInstaller: SaverVideoInstalling,
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
        // `NoopWallpaper()` ở đây chứ không làm default argument: biểu thức
        // mặc định chạy ở ngữ cảnh nonisolated, mà `NoopWallpaper.init` là
        // `@MainActor` (cùng ca với `TranslateController` bên dưới).
        self.wallpaper = wallpaper ?? NoopWallpaper()
        // KHÔNG có default `?? SaverVideoInstaller()` như `wallpaper` ở trên:
        // fallback của wallpaper là inert, còn fallback của installer trỏ vào
        // container THẬT của máy và `install` XOÁ những gì đang nằm đó. Bắt
        // buộc truyền vào là cách duy nhất chặn một test quên tiêm seam rồi
        // xoá video screensaver thật của người dùng.
        self.saverInstaller = saverInstaller
        self.dbPath = dbPath
        self.defaultDBPath = defaultDBPath
        self.defaults = defaults
        self.bundleID = bundleID
        hotkey = translate.currentHotkey
        hotkeyIsRegistered = translate.isHotkeyRegistered
        loginItemState = loginItem.state
        runAtLogin = loginItem.state != .off
        vitalsSettings = vitals.currentSettings
        wallpaperEnabled = self.wallpaper.isEnabled
        wallpaperVideoURL = self.wallpaper.videoURL
    }

    /// Đọc lại mọi thứ có thể đã đổi sau lưng cửa sổ này: login item bị tắt
    /// trong System Settings, quyền duyệt vừa được cấp, hotkey bị app khác
    /// giành mất, hay cặp ngôn ngữ đổi từ chính popup tra từ.
    ///
    /// PHẢI được gọi từ `SettingsWindowController.show()`, không phải chỉ
    /// `.onAppear`: `close()` chỉ order-out cửa sổ chứ không tháo content
    /// view, nên SwiftUI không bao giờ thấy root view biến mất và
    /// `.onAppear` chỉ chạy đúng MỘT lần cho cả vòng đời app — đo được:
    /// `appears=1` sau ba vòng mở/đóng.
    public func refreshFromSystem() {
        readLoginItemState()
        hotkey = translate.currentHotkey
        hotkeyIsRegistered = translate.isHotkeyRegistered
        vitalsSettings = vitals.currentSettings
        languages = backend.languages()
        recentLanguages = backend.recentLanguages()
        langConfig = backend.langConfig()
        wallpaperEnabled = wallpaper.isEnabled
        wallpaperVideoURL = wallpaper.videoURL
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

    // MARK: - Hình nền video

    /// Luôn đọc LẠI từ controller sau khi đặt: controller mới là nơi giữ sự
    /// thật (nó có thể từ chối — vd. chưa có video — mà UI không biết).
    public func setWallpaperEnabled(_ on: Bool) {
        wallpaper.setEnabled(on)
        wallpaperEnabled = wallpaper.isEnabled
        wallpaperVideoURL = wallpaper.videoURL
        status = on && wallpaperVideoURL == nil
            ? "Đã bật — chọn một video để hiện hình nền."
            : (on ? "Đã bật hình nền video." : "Đã tắt hình nền video.")
    }

    /// Trả về `Task` để test `await` được — copy chạy ngoài main thread, và một
    /// test đọc `saverSyncStatus` ngay sau lời gọi sẽ đọc trúng `.syncing`.
    @discardableResult
    public func setWallpaperVideo(_ url: URL?) -> Task<Void, Never> {
        wallpaper.setVideo(url)
        wallpaperEnabled = wallpaper.isEnabled
        wallpaperVideoURL = wallpaper.videoURL
        status = url.map { "Đã chọn \($0.lastPathComponent)." } ?? "Đã bỏ video."
        return syncSaverVideo(url)
    }

    /// Việc đồng bộ gần nhất đang xếp hàng — mỗi lần gọi mới PHẢI đợi lần
    /// TRƯỚC xong rồi mới đụng file, nếu không `install`/`clear` của hai lần
    /// gọi chạy song song trên CÙNG một đích, và thứ tự HOÀN THÀNH (không
    /// phải thứ tự GỌI) sẽ quyết định nội dung container.
    private var saverSyncTask: Task<Void, Never>?
    /// Tăng ở MỌI lần gọi `syncSaverVideo`. Đối chiếu ở cuối task — một lần
    /// gọi bị một lần gọi SAU vượt mặt (đã có generation mới hơn) thì kết quả
    /// của nó bị BỎ, không được ghi vào `saverSyncStatus`: chọn video A rồi
    /// đổi sang B trước khi A copy xong không được để A xong TRỄ rồi đè
    /// `.synced`/`.failed` của A lên đúng trạng thái mà B vừa ghi.
    private var saverSyncGeneration = 0

    private func syncSaverVideo(_ url: URL?) -> Task<Void, Never> {
        let installer = saverInstaller
        saverSyncGeneration += 1
        let generation = saverSyncGeneration
        let previous = saverSyncTask

        guard let url else {
            saverSyncStatus = .idle
            let task = Task {
                // Đợi lần gọi TRƯỚC xong rồi mới đụng file — xem chú thích ở
                // `saverSyncTask`.
                await previous?.value
                await Task.detached { try? installer.clear() }.value
            }
            saverSyncTask = task
            return task
        }

        saverSyncStatus = .syncing
        let task = Task { [weak self] in
            await previous?.value
            // Video vài trăm MB: copy trên main thread làm treo cửa sổ Settings.
            let failure: String? = await Task.detached {
                do {
                    try installer.install(url)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            // Chỉ lần gọi MỚI NHẤT mới được ghi trạng thái — xem chú thích ở
            // `saverSyncGeneration`.
            guard let self, self.saverSyncGeneration == generation else { return }
            let next: SaverSyncStatus = failure.map { .failed($0) } ?? .synced
            self.saverSyncStatus = next
        }
        saverSyncTask = task
        return task
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
            currentDB: dbPath, toDirectory: directory, store: maintenance, verdict: verdict,
            // Spec §5 bước 2: đóng popup ngay TRƯỚC `kt_close()`, và chỉ khi
            // thật sự tới bước đó — popup còn hiện là nơi duy nhất có thể sinh
            // một `lookup` mới lúc store sắp đóng, nhưng một thư mục bị từ
            // chối ở bước 1 thì không có lý do gì để đóng nó.
            willCloseStore: { self.translate.hidePopup() }
        ) {
        case .moved(let to, let oldRenamedTo):
            // Ghi override CHỈ ở nhánh này: `DatabaseLocation.resolve` chỉ
            // kiểm sự tồn tại của file, nên một override trỏ vào thư mục chưa
            // có db sẽ âm thầm rơi về mặc định (ràng buộc mang sang từ Task 4).
            DatabaseLocation.setOverride(to.deletingLastPathComponent(), defaults: defaults)
            dbPath = to
            storeIsOpen()
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
        case .failed(let reason, let storeStillOpen):
            // CHỈ gỡ cảnh báo khi `DataRelocation` khẳng định store đang mở —
            // năm trong sáu đường `.failed` là guard pre-flight, return trước
            // cả `closeStore()`, nên chúng không chứng minh gì cả.
            if storeStillOpen { storeIsOpen() }
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
        // Spec §5 bước 2 (áp cho cả `.everything`, nhánh duy nhất gọi
        // `kt_close`): popup phải đóng trước khi store bị đóng.
        if scope == .everything { translate.hidePopup() }

        let outcome = DataReset(backend: backend, defaults: defaults)
            .perform(scope, dbPath: dbPath, defaultDBPath: defaultDBPath, bundleID: bundleID)
        let succeeded = outcome == .done

        switch scope {
        case .history:
            if succeeded { storeIsOpen() }
            status = succeeded ? "Đã xoá lịch sử tra." : "Không xoá được lịch sử — db chưa đổi gì."
        case .savedWords:
            if succeeded { storeIsOpen() }
            status = succeeded ? "Đã xoá từ đã lưu." : "Không xoá được từ đã lưu — db chưa đổi gì."
        case .everything:
            switch outcome {
            case .failedNothingRemoved:
                // Store không chịu đóng. Theo giao kèo `StoreMaintaining`,
                // `false` nghĩa là CHƯA đóng được gì — db, companion và
                // preference còn nguyên, và store nhiều khả năng vẫn đang mở,
                // nên KHÔNG bật `needsRestart`. Nói "đã xoá sạch" ở đây là
                // một câu sai theo hướng nguy hiểm nhất: người dùng tin dữ
                // liệu đã mất và không tra lại nữa.
                status = "Không đóng được db nên chưa xoá gì cả — dữ liệu vẫn nguyên. Thoát và mở lại KuroTools rồi thử lại."
                return
            case .removedButStoreClosed:
                needsRestart = true
                status = "Đã xoá sạch nhưng không mở lại được db. Hãy thoát và mở lại KuroTools."
                return
            case .done:
                break
            }
            // 🔑 `perform` mở lại store ở `defaultDBPath` (nó vừa xoá cả
            // domain `UserDefaults`, tức xoá luôn override vị trí db), nhưng
            // nó vẫn trả `Bool` — không có gì buộc chỗ này đi theo. Quên dòng
            // dưới thì UI chỉ vào thư mục tuỳ chỉnh cũ trong khi db thật đã
            // nằm ở chỗ mặc định.
            dbPath = defaultDBPath
            storeIsOpen()

            // Spec §6 mức 3: đưa hotkey về ⌘⇧D và **đăng ký lại ngay**.
            // `removePersistentDomain` chỉ xoá preference ĐÃ LƯU; tổ hợp cũ
            // vẫn đang sống với hệ thống tới khi thoát app, và tới lần khởi
            // động sau nó âm thầm thành ⇧⌘D — có thể đang bị app khác giữ,
            // không ai báo cho người dùng. `applyHotkey` tự lo cả gỡ đăng ký,
            // đăng ký lại lẫn ghi preference.
            translate.applyHotkey(.default)
            hotkey = translate.currentHotkey
            hotkeyIsRegistered = translate.isHotkeyRegistered

            // 🔑 `removePersistentDomain` dọn sạch kho preference, nhưng
            // `VitalsController` giữ MỘT BẢN SAO nạp từ lúc khởi tạo — lần
            // `apply()` kế tiếp (người dùng nhích bất kỳ control nào trong tab
            // Vitals) sẽ ghi lại đủ SÁU khoá cũ xuống đĩa. Không có dòng dưới
            // đây thì "trở lại như vừa cài" là một câu sai: kho bị đầu độc
            // lại, không chỉ là một bản sao cũ trong bộ nhớ.
            applyVitals(Vitals.Settings())

            status = "Đã xoá sạch. Db mới nằm ở \(dbDirectory.path); \(hotkeyOutcomeAfterReset())"
        }
    }

    /// Nửa sau của dòng phản hồi sau khi xoá sạch, nói ĐÚNG chuyện gì đã xảy
    /// ra với phím tắt.
    ///
    /// Câu hỏi ở đây có HAI biến, và không vị từ đơn nào trả lời được nó —
    /// hai lần vá trước mỗi lần chọn một vị từ, và mỗi cái nói dối ở đúng cái
    /// ô mà cái kia đúng:
    ///
    /// - Chỉ `hotkeyIsRegistered`: `applyHotkey` ROLLBACK khi tổ hợp mới bị
    ///   chiếm — nó đăng ký lại tổ hợp CŨ và đặt cờ theo kết quả lần đăng ký
    ///   lại đó, gần như luôn `true`. Người dùng có tổ hợp riêng vì thế được
    ///   khoe "phím tắt trở lại ⌃⌥J", gọi tên đúng tổ hợp mà spec §6 mức 3
    ///   vừa bảo phải bỏ.
    /// - Chỉ `hotkey == .default`: người dùng CHƯA từng đổi phím tắt và ⇧⌘D
    ///   đang bị app khác giữ thì vị từ này vẫn đúng, nên nhánh thành công
    ///   bắn — trong khi cảnh báo cam ngay phía trên trong tab Chung nói phím
    ///   tắt KHÔNG hoạt động. Hai câu mâu thuẫn trong cùng một cửa sổ.
    ///
    /// Nên thân hàm liệt kê cả bốn ô của
    /// `(hotkey == .default) × hotkeyIsRegistered`, và **chỉ ô (đúng, đúng)
    /// mới là thành công**. Ba ô còn lại nói ba chuyện khác nhau vì trạng thái
    /// của chúng khác nhau thật: (default, chưa đăng ký) và (không default,
    /// chưa đăng ký) đều là "không có phím tắt nào đang sống", còn
    /// (không default, đã đăng ký) là "tổ hợp cũ vẫn đang chạy, nhưng cấu hình
    /// đã về mặc định". Bốn ô đó có bốn test mang đúng tên ô trong
    /// `SettingsModelTests` — đừng gộp lại thành một vị từ nữa.
    private func hotkeyOutcomeAfterReset() -> String {
        let restored = HotkeyCombo.default.displayString
        // Liệt kê thẳng cả BỐN ô của `(tổ hợp mặc định có phải tổ hợp hiện tại
        // không) × (nó có đang sống với hệ thống không)`. Mỗi lần trước đây
        // chọn MỘT trong hai vị từ này làm cổng cho nhánh "thành công" đều
        // đúng ở một ô và nói dối ở ô kia — `hotkeyIsRegistered` một mình nói
        // dối khi người dùng có tổ hợp riêng, `hotkey == .default` một mình
        // nói dối khi người dùng CHƯA từng đổi phím tắt và ⇧⌘D đang bị chiếm.
        // Chỉ ô (đúng, đúng) mới là thành công.
        //
        // Preference đã bị xoá sạch nên `HotkeyPreference.load` ở lần khởi
        // động sau trả `.default` — cấu hình ĐÃ về ⇧⌘D đúng spec §6 mức 3 ở cả
        // bốn ô; ba ô còn lại chỉ khác nhau ở chỗ CÁI GÌ đang thật sự sống.
        switch (hotkey == .default, hotkeyIsRegistered) {
        case (true, true):
            return "phím tắt trở lại \(restored)."
        case (true, false), (false, false):
            // Không có gì đang sống: hoặc ⇧⌘D bị chiếm và không có tổ hợp cũ
            // nào để quay về, hoặc quay về rồi mà đăng ký lại cũng hỏng.
            return """
            cấu hình phím tắt đã về \(restored) nhưng \(restored) đang bị app khác giữ — \
            hiện không có phím tắt nào hoạt động, chọn tổ hợp khác trong tab Chung.
            """
        case (false, true):
            // Controller đã rollback về tổ hợp cũ và tổ hợp đó vẫn sống — nói
            // rõ cả thứ đang chạy NGAY BÂY GIỜ lẫn chuyện lần khởi động sau.
            // "CÓ THỂ sẽ không hoạt động", không phải "sẽ không": app đang giữ
            // \(restored) có thể đã thoát trước lần khởi động đó, và app này
            // không có cách nào biết trước điều ấy.
            return """
            cấu hình phím tắt đã về \(restored) nhưng \(restored) đang bị app khác giữ — \
            hiện vẫn đang chạy \(hotkey.displayString), và lần khởi động sau phím tắt có thể \
            sẽ không hoạt động. Chọn tổ hợp khác trong tab Chung.
            """
        }
    }

    /// Đánh dấu "có một store chắc chắn đang mở". Gọi ở MỌI đường kết thúc như
    /// vậy — banner đỏ nằm lì sau khi app đã tự phục hồi bảo người dùng thoát
    /// một app đang chạy tốt.
    private func storeIsOpen() {
        needsRestart = false
    }

    // MARK: - Vitals

    /// Một đường DUY NHẤT vào preference của Vitals: `VitalsController.apply`
    /// còn phải đẩy ngưỡng xuống `FanController` và đặt lại nhịp timer, nên
    /// ghi thẳng `UserDefaults` từ tab là cách làm UI báo đã đổi trong khi hệ
    /// thống chạy theo giá trị cũ.
    public func applyVitals(_ settings: Vitals.Settings) {
        vitals.apply(settings)
        // Đọc LẠI từ controller, không gán `settings`: controller mới là nơi
        // giữ sự thật, và một bản sao gán thẳng sẽ trôi đi nếu `apply` từ chối
        // hay chuẩn hoá gì đó.
        vitalsSettings = vitals.currentSettings
        status = "Đã lưu cài đặt theo dõi."
    }

    // MARK: - Ngôn ngữ (tab Dịch đọc/ghi qua backend)

    /// Trả về thứ backend THỰC SỰ lưu, không phải thứ vừa chọn: `LangConfig::new`
    /// phía Rust sửa va chạm (đích trùng nguồn, v.v.), nên hai giá trị có thể
    /// khác nhau và tab phải hiển thị lại giá trị trả về.
    @discardableResult
    public func setLangConfig(source: String?, target: String, other: String) -> LangConfig? {
        let saved = backend.setLangConfig(source: source, target: target, other: other)
        // Lưu hỏng: đọc lại thứ backend đang giữ để picker không đứng ở một
        // giá trị chưa bao giờ được ghi.
        langConfig = saved ?? backend.langConfig()
        recentLanguages = backend.recentLanguages()
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
    /// Dựng model cho test mà không đụng gì THẬT: db ở thư mục tạm, backend
    /// trơ, `TranslateController()` chưa gọi `start()` nên không mở store lẫn
    /// đăng ký hotkey nào.
    ///
    /// `defaults` là tham số BẮT BUỘC: bản trước tự mint một suite
    /// `kurotools.settings.forTesting.<UUID>` mà không ai dọn, và mỗi lần chạy
    /// bộ test lại để lại một file plist trong `~/Library/Preferences` của máy
    /// thật. Test phải truyền suite của chính nó — cái nó đã
    /// `removePersistentDomain` trong `tearDown`.
    static func forTesting(
        loginItem: LoginItemControlling,
        defaults: UserDefaults,
        bundleID: String,
        wallpaper: WallpaperControlling? = nil,
        saverInstaller: SaverVideoInstalling = NoopSaverInstaller()
    ) -> SettingsModel {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        return SettingsModel(
            translate: TranslateController(),
            vitals: VitalsController(defaults: defaults),
            backend: InertBackend(),
            loginItem: loginItem,
            wallpaper: wallpaper,
            saverInstaller: saverInstaller,
            dbPath: tmp.appendingPathComponent(DatabaseMigration.databaseName),
            defaultDBPath: tmp.appendingPathComponent(DatabaseMigration.databaseName),
            defaults: defaults,
            bundleID: bundleID)
    }
}
#endif
