import AppKit
import SwiftUI

/// Model của cổng xin quyền Accessibility. Port từ
/// `~/Dev/ktranslate/src/components/PermissionGate.tsx` +
/// `src-tauri/src/commands.rs::open_accessibility_settings`.
///
/// Tách riêng khỏi `PermissionGateView` (cùng khuôn `SourceActionsModel`
/// trong SourceActionsView.swift): timer + closure escaping cần một reference
/// type để mutate được `asked`/`timer` từ trong callback — một `View` là
/// struct, gọi `mutating func` từ closure escaping của `Timer` không hợp lệ.
@MainActor
public final class PermissionGateModel: ObservableObject {
    /// Xem PermissionGate.tsx: `POLL_MS`.
    private static let pollInterval: TimeInterval = 0.5

    /// Đường dẫn sâu bốn tầng vào đúng pane Accessibility — macOS đã đổi tên
    /// nó hơn một lần, deep-link tránh phải mô tả đường bấm bằng lời (dễ vỡ
    /// theo phiên bản hệ điều hành). Đối chiếu 1:1 với hằng số trong
    /// `open_accessibility_settings` của bản Tauri.
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private let backend: TranslateBackend
    private let onGranted: () -> Void

    /// Đổi chữ nút "Grant access" → "Open System Settings again" sau lần bấm
    /// đầu — tín hiệu y hệt bản React dùng, để không lặp lại đúng một dòng
    /// "cấp quyền" vô nghĩa nếu người dùng đã bấm rồi mà quay lại panel này.
    @Published public var asked = false

    private var timer: Timer?

    public init(backend: TranslateBackend, onGranted: @escaping () -> Void) {
        self.backend = backend
        self.onGranted = onGranted
    }

    /// Poll trong khi cổng đang hiện, dừng khi view biến mất
    /// (`PermissionGateView.onDisappear` gọi `stopPolling`) để không có timer
    /// nào chạy nền vô ích sau khi người dùng đã rời màn hình này.
    ///
    /// Bắt buộc phải POLL, không phải hỏi một lần: quyền được cấp ở System
    /// Settings — một process khác hẳn — nên app này không có cách nào được
    /// chủ động thông báo khi nó đổi; không poll thì người dùng phải khởi
    /// động lại app sau khi cấp quyền, đúng thứ UX mà bản gốc cố tránh.
    ///
    /// `Timer(timeInterval:repeats:)` + `RunLoop.main.add(_:forMode: .common)`
    /// thay vì `Timer.scheduledTimer`, và `MainActor.assumeIsolated` trong
    /// closure — cùng khuôn `AppDelegate.startTimer` (KuroVitals): closure
    /// của Timer không tự động thừa hưởng cô lập `@MainActor` của class dù
    /// bản thân nó luôn chạy trên main run loop.
    public func startPolling() {
        stopPolling()
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        // hasAccessibility (check), KHÔNG PHẢI requestAccessibility: gọi lại
        // request hai lần mỗi giây sẽ bật lại hộp thoại hệ thống ngay trong
        // lúc người dùng đang đọc nó.
        guard backend.hasAccessibility() else { return }
        stopPolling()
        onGranted()
    }

    public func grantAccess() {
        asked = true
        // Best-effort, kết quả bỏ qua: giá trị Bool trả về chỉ nói hộp thoại
        // hệ thống có bật lên được không (đã hỏi trước đó thì macOS không
        // hỏi lại lần hai), không nói quyền đã thật sự được cấp hay chưa —
        // câu trả lời đó chỉ tới qua `poll()` ở trên.
        _ = backend.requestAccessibility()
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
    }
}

/// Hiện khi macOS chưa cấp quyền Accessibility. Port từ
/// `~/Dev/ktranslate/src/components/PermissionGate.tsx` — ba điều bắt buộc,
/// học từ đúng cách luồng mặc định của macOS hay đi sai:
///
/// 1. **Giải thích trước khi hỏi.** Hộp thoại của macOS không nói vì sao, nên
///    hỏi lạnh sẽ đọc như một app đòi kiểm soát máy.
/// 2. **Poll việc cấp quyền** (`PermissionGateModel.startPolling`) — không ai
///    phải khởi động lại app.
/// 3. **Không bao giờ cụt đường.** Từ chối là một lựa chọn được hỗ trợ: chép
///    trước rồi bấm hotkey không cần quyền gì cả. "Continue without it" là
///    một đường đi thật, không phải một lời an ủi.
public struct PermissionGateView: View {
    @StateObject private var model: PermissionGateModel
    let onSkip: () -> Void

    public init(backend: TranslateBackend, onGranted: @escaping () -> Void, onSkip: @escaping () -> Void) {
        _model = StateObject(wrappedValue: PermissionGateModel(backend: backend, onGranted: onGranted))
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Let KuroTools read your selection")
                .font(.system(size: 15, weight: .semibold))

            Text("""
            To look up the text you highlight in other apps, macOS requires \
            Accessibility access. KuroTools uses it for one thing only: \
            copying your current selection when you press the hotkey. Your \
            clipboard is put back exactly as it was.
            """)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            // Bất biến 3 (task-16-brief.md): riêng cho bản gộp này, chưa từng
            // có ở bản Tauri gốc — Tra/KTranslate chạy dưới bundle id
            // `com.kurovu.ktranslate`, KuroTools là `com.kurovu.kurotools`.
            // macOS cấp quyền THEO BUNDLE ID, nên với nó đây là một app hoàn
            // toàn mới; mục cũ trong danh sách Accessibility không cấp quyền
            // hộ. Không nói rõ câu này, người từng cấp quyền cho Tra sẽ thấy
            // popup cứ đòi quyền mãi và tưởng app lỗi.
            Text("""
            If "Tra" or "KTranslate" already shows granted access, that's \
            the old app — KuroTools has a new identity to macOS and needs \
            its own, separate grant.
            """)
            .font(.system(size: 12))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                Button(action: model.grantAccess) {
                    Text(model.asked ? "Open System Settings again" : "Grant access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onSkip) {
                    Text("Continue without it")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 2)

            Text("Without access, KuroTools still works — copy the text first, then press the hotkey.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
        // Bất biến 4 (task-16-brief.md): bản React tắt hẳn dismiss-on-blur
        // trong lúc màn hình này hiện, vì panel Tauri CÓ activate và blur khi
        // System Settings lấy focus sẽ ẩn mất nó ngay lúc người dùng vừa bấm.
        // Panel của KuroTools LÀ NSPanel `.nonactivatingPanel` (PopupPanel.swift)
        // và CÓ trở thành key window — `PopupPanel.show()` gọi `panel.makeKey()`
        // (commit `c2829c6`), sửa lại khẳng định sai ở đây (M-4, final
        // review). Lý do đúng blur-to-hide không tồn tại: `hidesOnDeactivate`
        // bị đặt `false` một cách CỐ Ý trên panel đó, và không có handler nào
        // gắn vào resignKey/deactivate để gọi `hide()` — không phải vì panel
        // không bao giờ thành key. Quyết định vẫn đúng, chỉ lý do trước đây
        // sai. Cố tình không thêm bất kỳ auto-hide nào (onDeactivate,
        // click-outside, v.v.) thay vào chỗ đó — thêm một cái sẽ tái tạo đúng
        // lỗi bản React phải vá.
    }
}
