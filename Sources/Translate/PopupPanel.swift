import AppKit

/// `NSPanel.canBecomeKeyWindow` mặc định `true` theo tài liệu Apple — đó vốn
/// là lý do `.nonactivatingPanel` tồn tại (một cửa sổ become-key được mà
/// không kéo app lên foreground). Nhưng đo được thật (Task 21 report, câu hỏi
/// 2): dù `show()` có gọi `panel.makeKey()`, phím vẫn bay tới app khác —
/// `frontmost process` ngay sau khi gửi phím là app đó, không phải app này, và
/// `value` của ô nhập luôn rỗng. Default không hiệu lực trong đúng tổ hợp
/// `[.borderless, .nonactivatingPanel]` này (có lẽ do initial `styleMask`
/// truyền vào `NSPanel(...)` khiến AppKit tự suy luận lại
/// `canBecomeKeyWindow` — không tài liệu hoá, chỉ đo được). Override tường
/// minh để không phụ thuộc vào suy luận ngầm đó.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Popup tra từ, hiện đè lên mọi app kể cả app đang fullscreen — mà KHÔNG bao
/// giờ cướp quyền active. Đối chiếu từng cờ với
/// `~/Dev/ktranslate/src-tauri/src/popup.rs` (bản Tauri/`NSWindowStyleMaskNonactivatingPanel`
/// cũ, cùng bài toán, đã trả giá để tìm ra đúng tổ hợp này).
@MainActor
public final class PopupPanel {
    private let panel: NSPanel
    private let vibrant = NSVisualEffectView()

    /// Bo góc panel. Chỉ áp DUY NHẤT một lần, ở layer native của content view
    /// (xem `init`) — bo thêm lần nữa trong SwiftUI để lại hai hình bo góc
    /// chồng nhau, cạnh anti-alias không triệt tiêu nhau và vệt blur rò ra ở
    /// góc. Vô hình trên nền tối, rõ mồn một trên nền sáng.
    private static let cornerRadius: CGFloat = 12

    /// Khoảng cách giữa con trỏ và góc popup, tính bằng point. Đủ để cửa sổ
    /// không mở đè ngay dưới con trỏ.
    private static let cursorGap: CGFloat = 12

    /// Bề rộng panel — CỐ ĐỊNH, không tự co giãn như chiều cao (khớp máy tra
    /// cứu hệ thống và bản Tauri cũ). `HeightMeasuringHost` (RootView.swift)
    /// phải đo với ĐÚNG width này — thiếu ràng buộc đó, `NSHostingView` đo với
    /// width gần-0 (frame khởi tạo `.zero`), `Text` wrap ở gần như mọi ký tự
    /// thay vì đúng bề rộng panel thật (Task 21 report, câu hỏi 1).
    public static let contentWidth: CGFloat = 420

    public var isVisible: Bool { panel.isVisible }

    /// TRUE khi panel này đang là key window — tức đang thật sự nhận bàn
    /// phím. Khác `isVisible`: panel `.nonactivatingPanel` có thể VẪN hiện
    /// trên màn hình (không tự ẩn khi mất key — `hidesOnDeactivate = false`)
    /// trong lúc một cửa sổ KHÁC của CHÍNH APP này (cửa sổ tiến trình của
    /// Vitals, hộp thoại xác nhận Kill) đã lấy mất key — dùng để phân biệt
    /// "popup đang hiện" với "phím vừa gõ thuộc về popup" (I-5, final review).
    public var isKeyWindow: Bool { panel.isKeyWindow }

    public init(content: NSView) {
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        // `setCollectionBehavior` THAY THẾ cả mask, không OR thêm — set một
        // lần ở đây và không bao giờ set lại lúc show, kẻo xoá mất cờ kia.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Panel này theo định nghĩa đè lên window của app KHÁC đang active —
        // mặc định `hidesOnDeactivate` sẽ ẩn nó ngay khi app đó active, tức
        // là gần như luôn luôn.
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // `.popover`, không phải `.hudWindow` — hudWindow là khối xám cố định
        // của overlay volume/brightness, không đổi màu theo nền phía sau.
        vibrant.material = .popover
        // `.behindWindow`, không phải `.withinWindow` — thứ cần blur là màn
        // hình PHÍA SAU cửa sổ (desktop, app khác), không phải nội dung ngay
        // trong window của chính mình. `.withinWindow` không blur được gì ở
        // đó, và cả điểm tồn tại của một popup trong suốt là làm mờ đúng cái
        // nền phía sau nó.
        vibrant.blendingMode = .behindWindow
        // Panel không-activate có thể không bao giờ trở thành "active" theo
        // nghĩa AppKit hiểu — ghim `.active` để vibrancy luôn render đúng
        // màu thay vì rơi vào trạng thái mờ nhạt của một view "inactive".
        vibrant.state = .active

        // Bo góc MỘT LẦN, ở đây — layer native của content view, không phải
        // SwiftUI `clipShape`. Một mask duy nhất clip mọi thứ bên trong cùng
        // lúc; không có gì phía sau ngoài desktop.
        vibrant.wantsLayer = true
        vibrant.layer?.cornerRadius = Self.cornerRadius
        vibrant.layer?.masksToBounds = true

        vibrant.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        vibrant.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: vibrant.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: vibrant.trailingAnchor),
            content.topAnchor.constraint(equalTo: vibrant.topAnchor),
            content.bottomAnchor.constraint(equalTo: vibrant.bottomAnchor),
        ])

        panel.contentView = vibrant
    }

    /// Hiện popup cạnh `point` (toạ độ màn hình kiểu AppKit — gốc dưới-trái,
    /// cùng hệ với `NSEvent.mouseLocation`), kẹp trong `visibleFrame` của
    /// đúng màn hình chứa con trỏ.
    ///
    /// Canh giữa màn hình chính sẽ mở popup ở màn hình anh không nhìn vào
    /// trên bàn nhiều màn hình — cảm giác y hệt hotkey không làm gì cả. Con
    /// trỏ là đại diện tốt nhất cho "người dùng đang ở đâu": văn bản vừa
    /// chọn nằm ngay dưới nó.
    /// Màn hình popup đang mở trên — ghim lại ở đây (không dò lại theo
    /// `panel.frame` mỗi lần) để `clampToVisibleFrame()` dùng đúng MỘT màn
    /// hình xuyên suốt vòng đời một lần hiện, kể cả khi `setContentHeight`
    /// gọi lại nó sau khi panel đã bị kẹp sát mép — dò lại lúc đó dễ nhầm
    /// sang màn hình bên cạnh (I-3, final review).
    private var currentScreen: NSScreen?

    public func show(near point: CGPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        currentScreen = screen
        if screen != nil {
            let size = panel.frame.size
            let origin = CGPoint(x: point.x + Self.cursorGap, y: point.y - size.height - Self.cursorGap)
            panel.setFrameOrigin(origin)
        }
        clampToVisibleFrame()

        // Áp lại MỖI LẦN show, không phải một lần lúc khởi tạo — app nằm ở
        // tray nhiều ngày liền và Tuấn có thể đổi giao diện hệ thống giữa
        // chừng. Không ghim thì chất liệu render kiểu sáng trên desktop tối:
        // chữ trắng trên panel trắng.
        panel.appearance = NSApp.effectiveAppearance

        // KHÔNG BAO GIỜ activate: không `NSApp.activate`, không
        // `makeKeyAndOrderFront` (bản GỘP hai bước làm một, cố tình tách ra
        // hai lệnh riêng bên dưới để không ai đọc nhầm dòng nào "là cái
        // activate"), không `NSWindow.show()`. Activation chính là thứ buộc
        // macOS thoát khỏi Space fullscreen — popup sẽ xuất hiện bằng cách
        // kéo người dùng ra khỏi thứ họ đang đọc.
        panel.orderFrontRegardless()

        // `makeKeyWindow()` — TÁCH RIÊNG khỏi lệnh trên, cố tình hai lệnh
        // chứ không gộp thành `makeKeyAndOrderFront:`. Đây KHÔNG phải một
        // ngoại lệ của luật "không activate" — nó là đúng lý do
        // `.nonactivatingPanel` (styleMask, `init`) tồn tại: cờ đó cho phép
        // MỘT CỬA SỔ trở thành key (nhận keyDown/text input) MÀ KHÔNG kéo
        // ứng dụng sở hữu nó lên foreground, không đổi app đang active,
        // không thoát Space fullscreen của app khác — ba thứ `NSApp.activate`
        // mới gây ra. Thiếu dòng này: ô nhập (`RootView`/`TextField`) không
        // bao giờ nhận được ký tự gõ vào, và không sự kiện bàn phím nào của
        // panel này (kể cả Escape mà `TranslateController` bắt bằng
        // `NSEvent.addLocalMonitorForEvents`) từng tới được app — local
        // monitor chỉ thấy sự kiện app ĐÃ nhận, và app không nhận được gì
        // nếu không cửa sổ nào của nó là key. `orderFrontRegardless()` một
        // mình chỉ lo phần "nhìn thấy trên màn hình", không lo phần "nhận
        // được phím".
        panel.makeKey()
    }

    public func hide() { panel.orderOut(nil) }

    /// Kẹp origin HIỆN TẠI của panel vào `visibleFrame` của `currentScreen`.
    /// Dùng chung bởi `show()` (lần mở đầu tiên) và `setContentHeight()`
    /// (I-3, final review) — trước bản vá này chỉ `show()` kẹp, bằng kích
    /// thước panel LÚC ĐÓ (160pt mặc định hoặc chiều cao của lần hiện trước).
    /// Layout SwiftUI đo chiều cao thật bất đồng bộ và báo về sau qua
    /// `onHeightChange` → `setContentHeight`, nên chuỗi hỏng là: kết quả
    /// NGẮN hiện trước → panel bị kẹp sát mép dưới màn hình ở `show()` →
    /// kết quả DÀI tới sau → `setContentHeight` phóng to panel LÊN TRÊN từ
    /// đúng cái mép dưới đó mà không kẹp lại — quá nửa panel nằm dưới mép
    /// màn hình, không với chuột tới được. Gọi lại hàm này ở cuối
    /// `setContentHeight` đóng đúng lỗ đó.
    private func clampToVisibleFrame() {
        guard let screen = currentScreen else { return }
        let visible = screen.visibleFrame
        var origin = panel.frame.origin
        let size = panel.frame.size
        // Kẹp cả hai chiều, `min` trước `max`: trên màn hình nhỏ hơn panel,
        // hai cận chéo nhau và `max` phải thắng để panel không tràn ra ngoài
        // mép trái/dưới.
        origin.x = max(min(origin.x, visible.maxX - size.width), visible.minX)
        origin.y = max(min(origin.y, visible.maxY - size.height), visible.minY)
        panel.setFrameOrigin(origin)
    }

    /// Chiều cao nội dung được phép co giãn tới. **Không có sàn**: panel cao
    /// đúng bằng nội dung, kể cả khi nội dung rất ngắn (một từ, một dòng lỗi)
    /// — sàn cũ `90` để lại một dải trống dưới mọi kết quả ngắn, mà tra một
    /// từ thì kết quả ngắn là trường hợp THƯỜNG, không phải ngoại lệ.
    ///
    /// Trần `520` giữ nguyên: cao hơn thế phải cuộn thay vì phình thêm mãi
    /// (`ScrollView` ở `RootView`), theo đúng máy tra cứu hệ thống
    /// (`MAX_HEIGHT` ở `~/Dev/ktranslate/src/window.ts`, tuy số ở đây khác vì
    /// đo trên NSView chứ không phải DOM).
    public static let contentHeightRange: ClosedRange<CGFloat> = 0...520

    /// Giữ MÉP TRÊN cố định khi đổi chiều cao: không có dòng dịch `origin.y`
    /// này, panel sẽ nhảy lên xuống mỗi lần kết quả tra cứu mới tới (vì
    /// `NSWindow` neo theo gốc dưới-trái, còn nội dung phải lớn/nhỏ dần từ
    /// mép trên xuống).
    public func setContentHeight(_ h: CGFloat) {
        var frame = panel.frame
        frame.origin.y += frame.height - h
        frame.size.height = h
        panel.setFrame(frame, display: true)
        // I-3 (final review): chiều cao mới có thể đẩy panel ra ngoài
        // `visibleFrame` mà `show()` đã kẹp bằng kích thước CŨ — kẹp lại.
        clampToVisibleFrame()
    }
}
