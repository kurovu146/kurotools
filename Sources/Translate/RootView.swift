import AppKit
import SwiftUI

/// Gốc của popup — ô nhập, điều phối trạng thái, Escape hai tầng, và cầu nối
/// giữa cây SwiftUI với chiều cao panel AppKit. Port từ
/// `~/Dev/ktranslate/src/App.tsx`, phần `return (...)`; comment trong đó giải
/// thích vì sao từng mảnh nằm ở đúng chỗ của nó.
public struct RootView: View {
    @ObservedObject var model: AppModel
    let backend: TranslateBackend
    let onHeightChange: (CGFloat) -> Void

    public init(model: AppModel, backend: TranslateBackend, onHeightChange: @escaping (CGFloat) -> Void) {
        self.model = model
        self.backend = backend
        self.onHeightChange = onHeightChange
    }

    public var body: some View {
        // `HeightMeasuringHost` bọc ĐÚNG phần nội dung cần đo — không phải
        // view gốc mà một tầng trên (Task 18, PopupPanel.init) sẽ pin đủ 4
        // cạnh vào vibrancy. Xem cảnh báo ở khai báo view đó bên dưới.
        HeightMeasuringHost(pickerOpen: model.pickerOpen, onHeightChange: onHeightChange) {
            PopupContent(model: model, backend: backend)
                // Tương đương `inert={pickerOpen}` của bản React: overlay bên
                // dưới không có focus trap (xem doc-comment
                // LanguagePickerView), nên khi picker mở, lớp nội dung này
                // phải hết tương tác VÀ biến mất khỏi cây accessibility — nếu
                // không, một lần Shift+Tab đưa focus xuống nút phía sau scrim
                // và Enter ở đó phát âm/lưu một từ từ phía sau picker.
                .allowsHitTesting(!model.pickerOpen)
                .accessibilityHidden(model.pickerOpen)
        }
        // `.overlay()`, không phải `ZStack` chứa cả hai: overlay không tham
        // gia vào kích thước của view nó phủ lên, nên nó nằm NGOÀI cây được
        // `HeightMeasuringHost` đo — một danh sách hơn trăm ngôn ngữ mở ra sẽ
        // không bao giờ phình `HeightMeasuringHost` (bất biến 1,
        // LanguagePickerView.swift).
        .overlay {
            if model.pickerOpen, let config = model.config, let picking = model.picking {
                LanguagePickerView(
                    selected: picking == .source ? (config.source ?? LanguageNames.auto) : config.target,
                    includeAuto: picking == .source,
                    languages: backend.languages(),
                    recent: backend.recentLanguages(),
                    onPick: { code in model.pick(picking, code: code) })
            }
        }
        // Cố ý KHÔNG bắt Escape trong LanguagePickerView (xem doc-comment ở
        // đó) — nó không có focus trap nên một handler khoanh trong subtree
        // của nó sẽ ngừng nhận phím ngay khi focus rơi ra ngoài. Gắn Ở ĐÂY,
        // tầng trên overlay, để một Escape luôn tới được bất kể focus đang ở
        // đâu trong picker hay trong ô nhập. `model.escape()` tự quyết định
        // hai tầng: đóng picker nếu đang mở (trả true), hay không làm gì (trả
        // false) để lần bấm kế tiếp — hoặc một trình xử lý khác ở tầng AppKit
        // ngoài RootView — coi như tín hiệu đóng cả popup. RootView không giữ
        // tham chiếu tới `PopupPanel`/`hide()` nên tầng thứ hai đó KHÔNG thể
        // thực thi từ file này — xem ghi chú trong report.
        .onExitCommand { _ = model.escape() }
    }
}

/// Nội dung sẽ được đo chiều cao — ô nhập, trạng thái idle/loading/kết quả,
/// và cổng quyền. Tách khỏi `RootView.body` để `HeightMeasuringHost` có đúng
/// MỘT view để bọc, không lẫn overlay picker vào cùng cây.
private struct PopupContent: View {
    @ObservedObject var model: AppModel
    let backend: TranslateBackend

    /// Chỉ ô nhập cần tự focus khi xuất hiện — cùng khuôn
    /// `LanguagePickerView.searchFocused`, khớp `autoFocus` của bản React.
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .needsPermission = model.state {
                PermissionGateView(
                    backend: backend,
                    onGranted: { model.state = .idle },
                    onSkip: { model.state = .idle })
            }

            // Ô nhập chỉ hiện khi `.idle` (bất biến 1, task-17-brief.md):
            // panel hệ thống không có ô nhập nào, và một khi kết quả đã hiện
            // thì cái ô chỉ là một thanh sáng chắn phía trên thứ người ta
            // thật sự muốn đọc.
            if case .idle = model.state {
                TextField("Look up a word…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(EdgeInsets(top: 14, leading: 14, bottom: 0, trailing: 14))
                    .focused($queryFocused)
                    .accessibilityLabel("Text to look up")
                    .onSubmit { model.run(model.query) }
                    .onAppear { queryFocused = true }
            }

            switch model.state {
            case .idle:
                Text("Select text anywhere, then press the hotkey.")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(EdgeInsets(top: 8, leading: 14, bottom: 14, trailing: 14))
            case .loading(let text):
                Text("Looking up “\(text)”…")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(14)
            case .done(let result):
                LookupResultView(
                    result: result,
                    // In nghiêng bám theo CẤU HÌNH, không bám theo kết quả
                    // (bất biến 3, task-17-brief.md) — `sourceLang` giữ cả
                    // ngôn ngữ đã cấu hình lẫn ngôn ngữ đoán được, nên riêng
                    // kết quả không nói được điều đó.
                    sourceDetected: model.config?.source == nil && result.sourceLang != nil,
                    backend: backend,
                    onPickSource: { model.picking = .source },
                    onPickTarget: { model.picking = .target })
            case .needsPermission:
                EmptyView()
            }
        }
    }
}

/// Cầu duy nhất đo chiều cao "tự nhiên" của nội dung popup và báo lên
/// `onHeightChange`. Port của `useHeightFitsContent` (`~/Dev/ktranslate/src/window.ts`).
///
/// 🔑 BẪY ĐO CHIỀU CAO (task-17-brief.md) — vì sao view này tồn tại thay vì
/// gọi thẳng `measuredHeight` trên view gốc: `content` mà `PopupPanel.init`
/// nhận (Task 18 dựng) bị pin đủ 4 cạnh vào lớp vibrancy, nên `frame.height`
/// của NÓ luôn bằng đúng chiều cao panel hiện tại — đo nó là một vòng lặp,
/// không phải một phép đo. `makeNSView` ở đây dựng một `NSHostingView` THỨ
/// HAI, lồng sâu hơn, không bị constraint nào của cha ép giãn — nó tự đặt
/// frame theo kích thước tự nhiên SwiftUI muốn (đúng điều kiện
/// `measuredHeight`, PanelSizing.swift, đòi hỏi), nên đo NÓ mới ra đúng câu
/// trả lời.
private struct HeightMeasuringHost<Content: View>: NSViewRepresentable {
    /// Giữ chiều cao đầy đủ khi picker mở (bất biến 4, task-17-brief.md).
    /// Picker là overlay NGOÀI cây được đo (`RootView.body`), nên nội dung
    /// bên trong không hề đổi khi nó mở/đóng — đo lại vẫn ra đúng chiều cao
    /// NGẮN của kết quả đang bị scrim che, làm panel co lại dưới picker. Ép
    /// thẳng lên cận trên thay vì đo — đúng theo `useHeightFitsContent`
    /// (window.ts): "the measurement is ignored outright rather than taken
    /// as a floor".
    let pickerOpen: Bool
    let onHeightChange: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSHostingView<Content> {
        NSHostingView(rootView: content())
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content()
        let height = pickerOpen
            ? PopupPanel.contentHeightRange.upperBound
            : measuredHeight(of: nsView, clampedTo: PopupPanel.contentHeightRange)
        onHeightChange(height)
    }
}
