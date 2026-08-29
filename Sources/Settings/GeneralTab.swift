import AppKit
import SwiftUI
import Translate
import UniformTypeIdentifiers

/// Cổng cuối trước một thao tác không lấy lại được. Tách khỏi view để đo được
/// — một `NSAlert` không chạy được trong test, nhưng luật "phải gõ đúng chữ"
/// thì phải có lưới.
enum ResetConfirmation {
    /// Gõ tay, không sinh từ `ResetScope`: đây là chuỗi người dùng phải gõ
    /// đúng từng ký tự, nên nó phải nằm ở đúng một chỗ và không bao giờ đổi
    /// theo một cái tên nội bộ nào.
    static let phrase = "XOÁ"

    static func canProceed(scope: ResetScope, typed: String) -> Bool {
        switch scope {
        case .history, .savedWords:
            return true
        case .everything:
            return typed.trimmingCharacters(in: .whitespacesAndNewlines) == phrase
        }
    }
}

/// Theo dõi ô gõ xác nhận trong `NSAlert` để bật/tắt nút xoá. `NSAlert` không
/// có sẵn đường nào để làm việc này — nút phải được tự khoá cho tới khi chuỗi
/// khớp.
private final class ConfirmationFieldDelegate: NSObject, NSTextFieldDelegate {
    private let onChange: (String) -> Void

    init(onChange: @escaping (String) -> Void) {
        self.onChange = onChange
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        onChange(field.stringValue)
    }
}

/// Tab đầu: phím tắt, chạy khi đăng nhập, và khối dữ liệu.
public struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hotkeySection
                Divider()
                loginItemSection
                Divider()
                wallpaperSection
                Divider()
                dataSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Phím tắt

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phím tắt tra từ").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                // Binding chỉ-đọc CÓ CHỦ Ý: ô ghi tự cập nhật tổ hợp vừa gõ
                // một cách lạc quan, nhưng nguồn sự thật là `model.hotkey` —
                // tổ hợp bị app khác chiếm phải bật ngược về giá trị cũ chứ
                // không được ở lại trên màn hình như thể đã nhận.
                HotkeyRecorderView(
                    combo: Binding(get: { model.hotkey }, set: { _ in }),
                    onRecorded: { model.recordHotkey($0) })
                    .frame(width: 140, height: 24)
                Text("Bấm vào ô rồi gõ tổ hợp mới.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            if !model.hotkeyIsRegistered {
                // Ca này gặp được ngay lần chạy ĐẦU, không cần người dùng làm
                // gì sai: một app khác đã giữ tổ hợp đó từ trước.
                Label(
                    "\(model.hotkey.displayString) đang bị app khác giữ — phím tắt hiện KHÔNG hoạt động. Chọn tổ hợp khác.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Chạy khi đăng nhập

    private var loginItemSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Chạy khi đăng nhập", isOn: Binding(
                get: { model.runAtLogin },
                set: { model.setRunAtLogin($0) }))
                .font(.system(size: 13))
            if model.loginItemState == .requiresApproval {
                // KHÔNG hiển thị như "tắt": `register()` đã thành công, macOS
                // chỉ đang chờ người dùng duyệt. Thiếu dòng này, công tắc
                // trông như bấm mà không có gì xảy ra.
                HStack(spacing: 8) {
                    Text("Đã đăng ký — cần anh duyệt trong System Settings ▸ General ▸ Login Items.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Mở") { openLoginItemsSettings() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
        }
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Hình nền video

    private var saverStatusText: String {
        switch model.saverSyncStatus {
        case .idle: return "Screensaver: chưa có video"
        case .syncing: return "Screensaver: đang chuẩn bị…"
        case .synced: return "Screensaver: đã đồng bộ"
        case .failed(let reason): return "Screensaver: lỗi — \(reason)"
        }
    }

    /// Cùng kiểu với `openLoginItemsSettings()` ở trên.
    private func openScreenSaverSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private var wallpaperSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hình nền video").font(.system(size: 13, weight: .semibold))

            Toggle("Bật hình nền video", isOn: Binding(
                get: { model.wallpaperEnabled },
                set: { model.setWallpaperEnabled($0) }))
                .font(.system(size: 13))

            HStack(spacing: 8) {
                Button("Chọn video…") { chooseWallpaperVideo() }
                if let url = model.wallpaperVideoURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Chưa chọn video")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Text("Video chạy sau icons trên desktop, tắt tiếng, lặp vô hạn — bật/tắt nhanh qua menu bar (K ▸ Hình nền video).")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)

            HStack(spacing: 8) {
                Text(saverStatusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Mở cài đặt Screen Saver") { openScreenSaverSettings() }
                    .font(.system(size: 11))
            }
            Text("""
Cùng video này chạy làm screensaver. Lần đầu phải cài bundle bằng ./scripts/install-saver.sh, rồi chọn "KuroTools Video" trong System Settings ▸ Screen Saver.
""")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseWallpaperVideo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Chọn"
        panel.message = "Chọn video làm hình nền desktop và screensaver"
        panel.allowedContentTypes = [.movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.setWallpaperVideo(url)
    }

    // MARK: - Dữ liệu

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dữ liệu").font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Db đang nằm ở").font(.system(size: 11)).foregroundColor(.secondary)
                Text(model.dbDirectory.path)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                // Khoá trong lúc một lần đổi chỗ đang chạy: `relocate` không
                // có guard tái nhập (model cũng chặn, đây là lớp thứ hai để
                // người dùng thấy được).
                Button("Đổi chỗ…") { chooseNewLocation() }
                    .disabled(model.isRelocating)
                Button("Mở trong Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.dbPath])
                }
                if model.isRelocating {
                    ProgressView().controlSize(.small)
                }
            }

            Divider().padding(.vertical, 2)

            Text("Xoá dữ liệu").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Button("Xoá lịch sử tra") { confirmReset(.history) }
                Button("Xoá từ đã lưu") { confirmReset(.savedWords) }
                Button("Xoá sạch…") { confirmReset(.everything) }
            }
            Text("Ba mức độc lập: xoá lịch sử không đụng tới từ đã lưu, và ngược lại.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
    }

    private func chooseNewLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Chọn"
        panel.message = "Chọn thư mục mới cho ktranslate.db"
        panel.directoryURL = model.dbDirectory
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        model.relocateDatabase(to: directory)
    }

    // MARK: - Xác nhận xoá

    private func confirmReset(_ scope: ResetScope) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = messageText(for: scope)
        alert.informativeText = informativeText(for: scope)
        alert.addButton(withTitle: "Xoá")
        alert.addButton(withTitle: "Huỷ")
        alert.buttons[0].hasDestructiveAction = true
        // Return KHÔNG được xoá gì: nút đầu của `NSAlert` mặc định nhận
        // `\r`, nên một cú Enter theo phản xạ sẽ xoá dữ liệu ngay khi hộp
        // thoại vừa hiện. Escape thì phải huỷ được — mặc định nó chỉ tự gắn
        // vào nút tên "Cancel", không phải "Huỷ".
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\u{1b}"

        var typed = ""
        var delegate: ConfirmationFieldDelegate?
        if scope == .everything {
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            field.placeholderString = ResetConfirmation.phrase
            delegate = ConfirmationFieldDelegate { text in
                typed = text
                alert.buttons[0].isEnabled = ResetConfirmation.canProceed(scope: scope, typed: text)
            }
            field.delegate = delegate
            alert.accessoryView = field
            alert.buttons[0].isEnabled = false
            alert.window.initialFirstResponder = field
        }

        let response = withExtendedLifetime(delegate) { alert.runModal() }
        guard response == .alertFirstButtonReturn,
              ResetConfirmation.canProceed(scope: scope, typed: typed)
        else { return }
        model.reset(scope)
    }

    private func messageText(for scope: ResetScope) -> String {
        switch scope {
        case .history: return "Xoá toàn bộ lịch sử tra?"
        case .savedWords: return "Xoá toàn bộ từ đã lưu?"
        case .everything: return "Xoá sạch mọi thứ?"
        }
    }

    private func informativeText(for scope: ResetScope) -> String {
        switch scope {
        case .history:
            return "Từ đã lưu và cài đặt giữ nguyên. Không hoàn tác được."
        case .savedWords:
            return "Lịch sử tra và cài đặt giữ nguyên. Không hoàn tác được."
        case .everything:
            return """
            Xoá db (cả lịch sử lẫn từ đã lưu) và mọi cài đặt — app trở lại như \
            vừa cài. Không hoàn tác được.

            Gõ \(ResetConfirmation.phrase) để bật nút xoá.
            """
        }
    }
}
