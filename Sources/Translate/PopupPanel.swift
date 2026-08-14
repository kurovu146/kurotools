import AppKit

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

    public var isVisible: Bool { panel.isVisible }

    public init(content: NSView) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
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
    public func show(near point: CGPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            var origin = CGPoint(x: point.x + Self.cursorGap, y: point.y - size.height - Self.cursorGap)
            // Kẹp cả hai chiều, `min` trước `max`: trên màn hình nhỏ hơn
            // panel, hai cận chéo nhau và `max` phải thắng để panel không
            // tràn ra ngoài mép trái/dưới.
            origin.x = max(min(origin.x, visible.maxX - size.width), visible.minX)
            origin.y = max(min(origin.y, visible.maxY - size.height), visible.minY)
            panel.setFrameOrigin(origin)
        }

        // Áp lại MỖI LẦN show, không phải một lần lúc khởi tạo — app nằm ở
        // tray nhiều ngày liền và Tuấn có thể đổi giao diện hệ thống giữa
        // chừng. Không ghim thì chất liệu render kiểu sáng trên desktop tối:
        // chữ trắng trên panel trắng.
        panel.appearance = NSApp.effectiveAppearance

        // KHÔNG BAO GIỜ activate: không `NSApp.activate`, không
        // `makeKeyAndOrderFront`, không `NSWindow.show()`. Activation chính
        // là thứ buộc macOS thoát khỏi Space fullscreen — popup sẽ xuất hiện
        // bằng cách kéo người dùng ra khỏi thứ họ đang đọc.
        panel.orderFrontRegardless()
    }

    public func hide() { panel.orderOut(nil) }

    /// Giữ MÉP TRÊN cố định khi đổi chiều cao: không có dòng dịch `origin.y`
    /// này, panel sẽ nhảy lên xuống mỗi lần kết quả tra cứu mới tới (vì
    /// `NSWindow` neo theo gốc dưới-trái, còn nội dung phải lớn/nhỏ dần từ
    /// mép trên xuống).
    public func setContentHeight(_ h: CGFloat) {
        var frame = panel.frame
        frame.origin.y += frame.height - h
        frame.size.height = h
        panel.setFrame(frame, display: true)
    }
}
