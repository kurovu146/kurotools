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
        // Người dùng có thể đã tắt login item trong System Settings, hoặc vừa
        // duyệt nó, giữa hai lần mở cửa sổ này.
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

    private init(model: SettingsModel) {
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
        // App là `LSUIElement` (không có Dock icon, không bao giờ tự thành app
        // active): thiếu `activate` thì cửa sổ hiện ra SAU LƯNG app đang dùng
        // và không nhận được bàn phím.
        NSApp.activate(ignoringOtherApps: true)
        controller.window.makeKeyAndOrderFront(nil)
    }
}
