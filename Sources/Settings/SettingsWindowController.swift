import AppKit
import SwiftUI

/// Ba tab + dòng phản hồi dùng chung ở đáy cửa sổ.
struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralTab(model: model).tabItem { Text("Chung") }
                TranslateTab(model: model).tabItem { Text("Dịch") }
                VitalsTab(model: model).tabItem { Text("Theo dõi") }
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if model.needsRestart {
                    // KHÔNG phải một dòng status thoáng qua: ở trạng thái này
                    // không có db nào đang mở và app không tự phục hồi được,
                    // nên lời nhắc phải nằm lại cho tới khi khởi động lại —
                    // một thao tác kế tiếp ghi đè `status` không được xoá nó.
                    Label(
                        "Không có db nào đang mở. Thoát và mở lại KuroTools trước khi tra tiếp.",
                        systemImage: "exclamationmark.octagon.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(model.status ?? " ")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 10, trailing: 14))
        }
        .frame(minWidth: 520, minHeight: 420)
        // Chỉ lo LẦN ĐẦU. Không đủ cho những lần mở sau: `close()` order-out
        // cửa sổ nhưng KHÔNG tháo content view, nên root view không bao giờ
        // "biến mất" với SwiftUI và `.onAppear` không bao giờ chạy lần hai
        // (đo được: `appears=1` sau ba vòng mở/đóng).
        // `SettingsWindowController.show()` mới là chỗ nạp lại mỗi lần.
        .onAppear { model.refreshFromSystem() }
    }
}

/// Một cửa sổ Settings cho cả app.
@MainActor
public final class SettingsWindowController {
    /// Một cửa sổ duy nhất cho cả app: bấm ⌘, lần thứ hai phải mang cửa sổ
    /// đang mở lên trước, không dựng cửa sổ thứ hai.
    private static var shared: SettingsWindowController?

    private let window: NSWindow
    /// Model mà `window`'s content view đang bọc. Về nguyên tắc CỐ ĐỊNH suốt
    /// vòng đời app — `AppDelegate` chỉ dựng một `SettingsModel` duy nhất và
    /// luôn truyền đúng tham chiếu đó vào `show(model:)`. `var`, không phải
    /// `let`: `adopt(_:)` bên dưới là lối thoát khi bất biến đó lỡ bị phá.
    private var model: SettingsModel

    private init(model: SettingsModel) {
        self.model = model
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "KuroTools Settings"
        window.contentView = NSHostingView(rootView: SettingsRootView(model: model))
        // NSWindow mặc định TỰ GIẢI PHÓNG khi đóng; giữ lại một tham chiếu
        // trong `shared` rồi mở lại nó sau khi đã bị giải phóng là một lần
        // dùng con trỏ chết. Cửa sổ này sống suốt vòng đời app, đúng như
        // `shared` giả định.
        window.isReleasedWhenClosed = false
        window.center()
    }

    public static func show(model: SettingsModel) {
        let controller = shared ?? SettingsWindowController(model: model)
        shared = controller
        if controller.model !== model {
            // Bất biến "AppDelegate chỉ dựng MỘT SettingsModel suốt vòng đời
            // app" đã bị phá bởi một call site mới nào đó. KHÔNG được
            // `precondition`/trap ở đây: process này gộp cả fan control lẫn
            // Settings, và một trap KHÔNG chạy `applicationWillTerminate` —
            // nơi fan được trả về auto. Fan sẽ kẹt nguyên RPM ép cuối cùng,
            // hậu quả nặng hơn hẳn bug Settings mà trap này định bắt.
            // `assertionFailure` bắt lỗi này ngay ở build debug (trap, dev
            // thấy liền) mà KHÔNG trap ở build release (`-O`, đúng bản
            // `swift build -c release` dùng để đóng gói) — người dùng cuối
            // không bao giờ dính một crash vì lỗi lập trình ở tầng Settings.
            // Release: "adopt" — dựng lại content view theo model MỚI và cập
            // nhật `model`, thay vì lặng lẽ tiếp tục hiện dữ liệu của model
            // CŨ mà lúc này không còn ai giữ tham chiếu tới (refresh nó cũng
            // vô nghĩa — không ai nhìn thấy kết quả).
            assertionFailure(
                "SettingsWindowController.show(model:) got a different SettingsModel instance than the one the shared window was built with — adopting it.")
            NSLog("KuroTools: SettingsWindowController.show(model:) got a second SettingsModel instance; adopting it.")
            controller.adopt(model)
        }
        // MỖI lần mở, không chỉ lần đầu: giữa hai lần mở, người dùng có thể đã
        // tắt login item trong System Settings, duyệt nó, đổi cặp ngôn ngữ từ
        // popup tra từ, hoặc một app khác đã giành mất phím tắt. `.onAppear`
        // của root view không bắt được những lần sau (xem chú thích ở đó).
        model.refreshFromSystem()
        // App là `LSUIElement` (không có Dock icon, không bao giờ tự thành app
        // active): thiếu `activate` thì cửa sổ hiện ra SAU LƯNG app đang dùng
        // và không nhận được bàn phím.
        NSApp.activate(ignoringOtherApps: true)
        controller.window.makeKeyAndOrderFront(nil)
    }

    /// Thay hẳn model cửa sổ đang bọc — chỉ gọi khi bất biến "một model suốt
    /// vòng đời" đã bị phá (xem `show(model:)`). `NSHostingView` không tự
    /// refit sang model khác, nên phải dựng lại `contentView`.
    private func adopt(_ newModel: SettingsModel) {
        model = newModel
        window.contentView = NSHostingView(rootView: SettingsRootView(model: newModel))
    }
}
