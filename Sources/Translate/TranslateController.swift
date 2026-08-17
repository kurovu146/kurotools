import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Điểm nối cuối cùng: hotkey toàn cục → capture → popup. Port kết hợp
/// `~/Dev/ktranslate/src-tauri/src/hotkey.rs` + `popup.rs`
/// (`toggle_with_selection`/`show_with_selection`) — gộp lại thành một class
/// vì ở đây không có tách process backend/frontend để chia theo hai file.
@MainActor
public final class TranslateController {
    private let backend: TranslateBackend
    private let model: AppModel
    private var panel: PopupPanel?
    private var hotkey: HotkeyMonitor?
    public private(set) var currentHotkey: HotkeyCombo = .default
    /// TRUE khi `currentHotkey` thực sự đang sống với hệ thống
    /// (`RegisterEventHotKey` đã thành công) — phân biệt "phím tắt của anh,
    /// đang hoạt động" với "phím tắt anh chọn, nhưng app khác đang giữ nó".
    /// Một settings UI KHÔNG được suy ra trạng thái này từ `currentHotkey`
    /// khác nil — `currentHotkey` luôn có giá trị (kể cả lúc đăng ký thất
    /// bại), chỉ cờ này mới nói lên hotkey có thật sự bắn được hay không.
    public private(set) var isHotkeyRegistered = false
    /// Từ `NSEvent.addLocalMonitorForEvents` — kiểu trả về là `Any?` theo
    /// chữ ký AppKit, không phải một type cụ thể.
    private var escapeMonitor: Any?

    /// TRUE từ lúc `showPopup()` gọi `captureAsync` tới khi completion của nó
    /// chạy (final review, follow-up của I-1) — panel chỉ `show()` BÊN TRONG
    /// completion đó, nên `panel.isVisible` ở TOÀN BỘ khoảng chờ này vẫn là
    /// `false` (có thể tới ~1.4s trên đường capture thất bại — main thread
    /// giờ RẢNH trong lúc đó, đúng mục đích của I-1, nên người dùng có đủ
    /// thời gian bấm hotkey lần nữa). Không có cờ này, `toggle()` sẽ luôn đọc
    /// "chưa hiện" và gọi `showPopup()` thêm một lần — hai lần ⌘C giả lập bắn
    /// vào app đang active, và toggle đi sai chiều (không đóng được lần bấm
    /// kế tiếp trong khi lần trước còn đang bay). Xem `decideToggle`
    /// (ToggleDecision.swift) cho bảng chân trị.
    private var isCapturing = false

    public init() {
        self.backend = KTranslateBridge.shared
        self.model = AppModel(backend: backend)
    }

    /// Dựng panel, nạp cấu hình ngôn ngữ, và đăng ký hotkey. Gọi đúng một lần
    /// lúc app khởi động — `dbPath` đã được resolve từ trước (xem
    /// `DatabaseMigration.resolveDatabase`, Task 19); hàm này không tự resolve,
    /// chỉ nhận sẵn qua tham số.
    public func start(dbPath: URL) {
        // M-1 (final review): trước bản vá, lỗi ở đây bị nuốt hoàn toàn — db
        // hỏng thì picker vẫn mở được (config load fail vẫn có fallback,
        // AppState.swift), nhưng CHỌN NGÔN NGỮ XONG KHÔNG GÌ XẢY RA, mãi mãi,
        // không một dòng log nào để bắt đầu debug từ đâu.
        if !KTranslateBridge.shared.start(dbPath: dbPath) {
            NSLog("KuroTools: kt_init failed for \(dbPath.path) — lookups will silently do nothing")
        }
        model.loadConfig()

        let root = RootView(
            model: model, backend: backend,
            onHeightChange: { [weak self] height in self?.panel?.setContentHeight(height) })

        // `DraggableHostingView`, không phải `NSHostingView` trần — đây CHÍNH
        // LÀ content view Task 10-11 để trống chờ (PanelSizing.swift): popup
        // không có titlebar, nên panel phải tự làm tay cầm kéo qua chính view
        // này. KHÔNG dùng view này làm nguồn đo chiều cao — xem chú thích
        // bên dưới.
        let hosting = DraggableHostingView(rootView: root)
        panel = PopupPanel(content: hosting)

        // `hosting` KHÔNG BAO GIỜ được dùng để đo chiều cao. Nó là view TRÊN
        // CÙNG mà `PopupPanel.init` đã pin đủ 4 cạnh vào lớp vibrancy
        // (PopupPanel.swift:63-70) — đo NÓ là một vòng lặp, không phải một
        // phép đo (đúng cảnh báo trong doc-comment
        // `HeightMeasuringHost`, RootView.swift): `frame.height` của nó luôn
        // bằng đúng chiều cao panel hiện tại. View đo được đúng cách là
        // `NSHostingView` THỨ HAI mà `HeightMeasuringHost` tự dựng bên trong
        // cây SwiftUI của `RootView` — riêng tư, TranslateController không
        // có tham chiếu tới nó. Auto-height dựa hoàn toàn vào
        // `onHeightChange` ở trên, tự bắn ngay từ lượt layout SwiftUI đầu
        // tiên (view đã nằm trong cây view của panel dù panel chưa hiện).

        installEscapeMonitor()

        registerHotkey(HotkeyPreference.load())
    }

    /// Cố đăng ký `combo` với hệ thống và ghi lại kết quả THẬT, thay vì gán
    /// `currentHotkey` trước rồi bỏ qua kết quả `register()` — tách khỏi
    /// phần dựng DB/panel còn lại của `start()` nên test được riêng
    /// (`KTranslateBridge.shared` là singleton cấp process; gọi `start()`
    /// đầy đủ trong test sẽ đụng store dùng chung của các file test khác).
    ///
    /// Không có tổ hợp "cũ" nào để quay về ở đây (khác `applyHotkey`, luôn
    /// có `previous` đã từng đăng ký) — nếu `combo` bị chiếm, hotkey đơn
    /// giản là chưa hoạt động cho tới lần `applyHotkey` kế tiếp. `currentHotkey`
    /// vẫn được gán bằng `combo` dù đăng ký thất bại, để UI biết "đây là
    /// tổ hợp đang được cấu hình" — `isHotkeyRegistered` mới là cờ nói lên
    /// nó có thật sự sống hay không.
    @discardableResult
    func registerHotkey(_ combo: HotkeyCombo) -> Bool {
        let monitor = HotkeyMonitor(keyCode: combo.keyCode, modifiers: combo.modifiers) {
            [weak self] in self?.toggle()
        }
        let registered = monitor.register()
        currentHotkey = combo
        isHotkeyRegistered = registered
        hotkey = monitor
        return registered
    }

    /// Đổi tổ hợp phím và đăng ký lại NGAY, không đợi khởi động lại app.
    ///
    /// Thất bại (gần như luôn là app khác đã chiếm tổ hợp) → quay về tổ hợp
    /// cũ và đăng ký lại nó. Người dùng bấm nhầm một tổ hợp bận không được
    /// phải trả giá bằng việc mất hotkey.
    @discardableResult
    public func applyHotkey(_ combo: HotkeyCombo) -> Bool {
        guard combo.isValid else { return false }
        let previous = currentHotkey
        hotkey?.unregister()

        let monitor = HotkeyMonitor(keyCode: combo.keyCode, modifiers: combo.modifiers) {
            [weak self] in self?.toggle()
        }
        if monitor.register() {
            hotkey = monitor
            currentHotkey = combo
            isHotkeyRegistered = true
            HotkeyPreference.save(combo)
            return true
        }

        let restored = HotkeyMonitor(keyCode: previous.keyCode, modifiers: previous.modifiers) {
            [weak self] in self?.toggle()
        }
        // Kiểm kết quả THẬT thay vì giả định luôn thành công — race hẹp
        // (vài lệnh C đồng bộ) giữa `unregister()` ở trên và `register()` ở
        // đây có thể để một app khác chiếm mất `previous`. Không kiểm thì
        // `hotkey` giữ một monitor CHƯA đăng ký, và người dùng mất hotkey
        // im lặng tới lần bấm/khởi động lại kế tiếp.
        let restoredOK = restored.register()
        hotkey = restored
        currentHotkey = previous
        isHotkeyRegistered = restoredOK
        return false
    }

    /// Đường hotkey: đóng nếu đang mở, mở nếu đang đóng.
    ///
    /// 🔑 BẤT BIẾN 2 (task-18-brief.md): panel `.nonactivatingPanel` không tự
    /// đóng khi mất focus (không có blur-to-hide — xem doc-comment
    /// `PermissionGateView`), và trước khi Escape nhận được phím
    /// (`installEscapeMonitor`) không có đường đóng nào khác cả. Thiếu
    /// toggle này, bấm hotkey một lần rồi popup nằm lì trên màn hình mãi mãi.
    ///
    /// Quyết định qua `decideToggle` (ToggleDecision.swift), không phải
    /// `if panel.isVisible` trần — bảng chân trị đó có một ô thứ ba
    /// (`isCapturing`) mà `panel.isVisible` một mình không phân biệt được
    /// (final review, follow-up của I-1): trong lúc một `captureAsync` đang
    /// bay, panel vẫn CHƯA hiện, nên logic hai nhánh cũ sẽ luôn coi lần bấm
    /// thứ hai là "mở" thay vì coi nó là trùng lặp với request đang chạy.
    public func toggle() {
        guard let panel else { return }
        switch decideToggle(isCapturing: isCapturing, isPanelVisible: panel.isVisible) {
        case .ignore: return
        case .hide: hidePopup()
        case .show: showPopup()
        }
    }

    /// 🔑 BẤT BIẾN 3 (task-18-brief.md): capture TRƯỚC, show SAU. Show trước
    /// sẽ cướp keyboard focus khỏi app đang giữ lựa chọn, nên Cmd+C giả lập
    /// bên trong `backend.capture()` đi vào cửa sổ của CHÍNH MÌNH thay vì app
    /// kia — mọi lần capture sẽ trả về rỗng. Đối chiếu
    /// `popup.rs::show_with_selection`, đúng cùng thứ tự.
    ///
    /// I-1 (final review): `captureAsync`, không phải `capture()` đồng bộ —
    /// đường thất bại của capture có thể mất tới ~1.4s (Rust
    /// `std::thread::sleep`), và app này GỘP cả Vitals: gọi đồng bộ trên
    /// `@MainActor` đóng băng menu bar nhiệt độ, menu quạt, và cửa sổ tiến
    /// trình trong lúc đó, không chỉ riêng popup dịch. `model.handle()` +
    /// `panel.show()` vẫn nằm trong CÙNG completion, đúng thứ tự capture-
    /// trước-show — tương đương `spawn_blocking { capture_now(); show(&app);
    /// emit(...) }` của bản gốc (`popup.rs::show_with_selection`).
    ///
    /// `isCapturing` bật NGAY TRƯỚC khi gọi `captureAsync`, tắt ở ĐẦU
    /// completion (final review, follow-up của I-1) — completion chỉ có một
    /// nhánh chung cho cả ba `CaptureOutcome` (`.text`/`.empty`/
    /// `.needsPermission`), nên tắt ở đây phủ hết mọi đường ra, không riêng
    /// đường thành công.
    private func showPopup() {
        isCapturing = true
        backend.captureAsync { [weak self] outcome in
            guard let self else { return }
            self.isCapturing = false
            self.model.handle(outcome)
            self.panel?.show(near: NSEvent.mouseLocation)
        }
    }

    /// Điểm gọi DUY NHẤT đóng popup — cả từ `toggle()` lẫn từ tier 2 của
    /// `installEscapeMonitor`, để không nơi nào quên bước dọn dẹp.
    ///
    /// `model.dismissed()` đứng TRƯỚC `panel.hide()`: xem doc-comment của nó
    /// (AppState.swift, commit 8e8e6a7) — đường toggle-đóng/Escape-tier-2
    /// không đi qua `handle()` lẫn `RootView`, nên đây là nơi DUY NHẤT dọn
    /// Timer poll quyền Accessibility nếu popup đang đóng lại đúng lúc cổng
    /// quyền hiện. An toàn gọi vô điều kiện — no-op ở mọi trạng thái khác.
    private func hidePopup() {
        model.dismissed()
        panel?.hide()
    }

    /// Bắt Escape TRƯỚC khi nó tới SwiftUI — `.onExitCommand` trong
    /// `RootView` (modifier Escape duy nhất khả dụng ở macOS 13) LUÔN tiêu
    /// thụ phím, không có cách "không tiêu thụ" để nhường responder chain
    /// (finding của Task 17, xem RootView.swift:49-58). Tier 2 (đóng cả
    /// popup khi `model.escape()` trả `false`) vì vậy không có nơi thực thi
    /// bên trong `RootView` — chỉ `TranslateController` mới cầm được tham
    /// chiếu tới `PopupPanel` để đóng nó.
    ///
    /// `NSEvent.addLocalMonitorForEvents`, không phải `addGlobalMonitor`:
    /// đây là Escape của CHÍNH app này khi panel đang là key window, không
    /// phải theo dõi phím của app khác — không cần và không nên đi qua
    /// đường cần quyền Accessibility.
    ///
    /// Luôn tiêu thụ (`return nil`) khi panel đang hiện: tier 1 (đóng picker)
    /// được xử lý tại đây thay vì nhường cho `RootView.onExitCommand` — gọi
    /// `model.escape()` một lần DUY NHẤT, dứt khoát, thay vì để sự kiện lọt
    /// xuống gọi lại lần hai (vô hại nếu có xảy ra vì `escape()`/`dismissed()`
    /// đều idempotent, nhưng không dựa vào đó làm đường chính).
    ///
    /// Guard theo `panel?.isKeyWindow`, KHÔNG PHẢI `panel?.isVisible` (I-5,
    /// final review) — `local monitor` thấy phím của MỌI cửa sổ trong CHÍNH
    /// app này, không riêng popup: panel `.nonactivatingPanel` không tự ẩn
    /// khi mất key (`hidesOnDeactivate = false`, PopupPanel.swift), nên nó có
    /// thể VẪN `isVisible == true` trong lúc người dùng đang gõ ở nơi khác
    /// của CÙNG app — ô tìm kiếm của cửa sổ tiến trình Vitals
    /// (`ProcessWindowController.swift`), hay hộp thoại xác nhận Kill process
    /// của chính cửa sổ đó. Guard cũ nuốt Escape của TOÀN APP bất cứ khi nào
    /// popup còn hiện: ô tìm kiếm không xoá được bằng Escape, và tệ hơn, hộp
    /// thoại "Kill process?" — `NSAlert.runModal()` — không huỷ được bằng
    /// Escape. `isKeyWindow` chỉ đúng khi phím này thật sự thuộc về panel.
    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == UInt16(kVK_Escape), self.panel?.isKeyWindow == true else {
                return event
            }
            if !self.model.escape() {
                self.hidePopup()
            }
            return nil
        }
    }

    /// Đối xứng với `HotkeyMonitor.deinit` (unregister Carbon hotkey +
    /// event handler). Chưa rò rỉ thật trong M1 — `TranslateController` sống
    /// suốt vòng đời app, đúng một instance, không bao giờ bị deinit trước
    /// khi process thoát — nhưng Task 20 sắp khoá cứng giả định đó vào
    /// `AppDelegate`, và thiếu đường dọn dẹp ở đây trong khi `HotkeyMonitor`
    /// (cùng file, cùng loại tài nguyên hệ thống) đã có là một bất đối xứng
    /// đáng vá trước khi ai đó tạo ra một instance thứ hai.
    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        hotkey?.unregister()
    }
}
