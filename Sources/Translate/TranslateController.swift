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
    /// Từ `NSEvent.addLocalMonitorForEvents` — kiểu trả về là `Any?` theo
    /// chữ ký AppKit, không phải một type cụ thể.
    private var escapeMonitor: Any?

    public init() {
        self.backend = KTranslateBridge.shared
        self.model = AppModel(backend: backend)
    }

    /// Dựng panel, nạp cấu hình ngôn ngữ, và đăng ký hotkey. Gọi đúng một lần
    /// lúc app khởi động — `dbPath` đã được resolve từ trước (xem
    /// `DatabaseMigration.resolveDatabase`, Task 19); hàm này không tự resolve,
    /// chỉ nhận sẵn qua tham số.
    public func start(dbPath: URL) {
        _ = KTranslateBridge.shared.start(dbPath: dbPath)
        model.loadConfig()

        let root = RootView(
            model: model, backend: backend,
            onHeightChange: { [weak self] height in self?.panel?.setContentHeight(height) })

        // `DraggableHostingView`, không phải `NSHostingView` trần — đây CHÍNH
        // LÀ content view Task 10-11 để trống chờ (PanelSizing.swift): popup
        // không có titlebar, nên panel phải tự làm tay cầm kéo qua chính view
        // này. KHÔNG dùng view này làm nguồn đo chiều cao (`fitToContent`) —
        // xem chú thích bên dưới.
        let hosting = DraggableHostingView(rootView: root)
        panel = PopupPanel(content: hosting)

        // Cố ý KHÔNG gọi `panel.fitToContent(hosting)` ở đây. `hosting` là
        // view TRÊN CÙNG mà `PopupPanel.init` đã pin đủ 4 cạnh vào lớp
        // vibrancy (PopupPanel.swift:63-70) — đo NÓ là một vòng lặp, không
        // phải một phép đo (đúng cảnh báo trong doc-comment
        // `HeightMeasuringHost`, RootView.swift): `frame.height` của nó luôn
        // bằng đúng chiều cao panel hiện tại. View đo được đúng cách là
        // `NSHostingView` THỨ HAI mà `HeightMeasuringHost` tự dựng bên trong
        // cây SwiftUI của `RootView` — riêng tư, TranslateController không
        // có tham chiếu tới nó. Auto-height dựa hoàn toàn vào
        // `onHeightChange` ở trên, tự bắn ngay từ lượt layout SwiftUI đầu
        // tiên (view đã nằm trong cây view của panel dù panel chưa hiện).

        installEscapeMonitor()

        let monitor = HotkeyMonitor { [weak self] in self?.toggle() }
        monitor.register()
        hotkey = monitor
    }

    /// Đường hotkey: đóng nếu đang mở, mở nếu đang đóng.
    ///
    /// 🔑 BẤT BIẾN 2 (task-18-brief.md): panel `.nonactivatingPanel` không tự
    /// đóng khi mất focus (không có blur-to-hide — xem doc-comment
    /// `PermissionGateView`), và trước khi Escape nhận được phím
    /// (`installEscapeMonitor`) không có đường đóng nào khác cả. Thiếu
    /// toggle này, bấm hotkey một lần rồi popup nằm lì trên màn hình mãi mãi.
    public func toggle() {
        guard let panel else { return }
        if panel.isVisible {
            hidePopup()
        } else {
            showPopup()
        }
    }

    /// 🔑 BẤT BIẾN 3 (task-18-brief.md): capture TRƯỚC, show SAU. Show trước
    /// sẽ cướp keyboard focus khỏi app đang giữ lựa chọn, nên Cmd+C giả lập
    /// bên trong `backend.capture()` đi vào cửa sổ của CHÍNH MÌNH thay vì app
    /// kia — mọi lần capture sẽ trả về rỗng. Đối chiếu
    /// `popup.rs::show_with_selection`, đúng cùng thứ tự.
    private func showPopup() {
        let outcome = backend.capture()
        model.handle(outcome)
        panel?.show(near: NSEvent.mouseLocation)
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
    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == UInt16(kVK_Escape), self.panel?.isVisible == true else {
                return event
            }
            if !self.model.escape() {
                self.hidePopup()
            }
            return nil
        }
    }
}
