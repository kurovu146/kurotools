import Foundation

/// Trạng thái hiển thị của popup — bốn khả năng loại trừ lẫn nhau.
public enum LookupState: Equatable {
    case idle
    case loading(String)
    case done(Lookup)
    case needsPermission
}

/// Bên nào của cặp ngôn ngữ đang được chọn qua picker.
public enum PickerSide: Equatable {
    case source
    case target
}

/// State machine của popup — cổng chuyển đổi giữa capture, lookup và language
/// picker. Port từ `~/Dev/ktranslate/src/App.tsx`; sáu bất biến trong đó vẫn
/// giữ nguyên ở đây, comment tại chỗ dùng giải thích lý do.
@MainActor
public final class AppModel: ObservableObject {
    private let backend: TranslateBackend

    @Published public var state: LookupState = .idle
    @Published public var query: String = ""
    @Published public var config: LangConfig?
    @Published public var picking: PickerSide?

    /// Chuỗi đã cho ra kết quả đang hiển thị, để đổi ngôn ngữ có thể chạy lại
    /// nó thay vì capture lại.
    private var lastText: String = ""

    /// Token thế hệ — cùng khuôn `SourceActionsModel.generation`
    /// (SourceActionsView.swift): đổi ngôn ngữ nhanh hai lần liên tiếp qua
    /// picker chạy `run()` hai lần, cả hai completion đều khớp
    /// `LookupState.done`, nên không có cách nào phân biệt "kết quả này còn
    /// mới không" chỉ từ kiểu của `state` — thiếu token này, completion của
    /// lần chạy TRƯỚC tới SAU completion của lần chạy SAU sẽ ghi đè kết quả
    /// đúng bằng một kết quả đã lỗi thời, không còn request nào đang chờ để
    /// sửa lại (I-6, final review).
    private var generation = 0

    public init(backend: TranslateBackend) {
        self.backend = backend
    }

    /// Picker thực sự đang hiện trên màn hình — không chỉ được yêu cầu.
    ///
    /// Một cái tên cho cả ba thứ phải đồng ý: overlay có hiện không, chiều cao
    /// panel, và có chặn tương tác phía sau không. `config` là `nil` cho tới
    /// khi FFI trả về và nil vĩnh viễn nếu đọc lỗi, trong khi nhãn cặp ngôn
    /// ngữ vẫn render (nó lấy từ *kết quả*, không từ config) — nên một cú
    /// click có thể yêu cầu mở picker mà không có picker nào để mở.
    public var pickerOpen: Bool { picking != nil && config != nil }

    /// Chỉ nhãn cặp ngôn ngữ cần cái này, và nó hiện "Auto" cho tới khi tới —
    /// một lần đọc lỗi không được chặn panel hiện kết quả tra.
    public func loadConfig() {
        config = backend.langConfig()
    }

    public func run(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bump TRƯỚC cả early-return: một `run("")` huỷ hẳn lookup đang chờ
        // của lần `run` trước đó, kẻo completion của nó tới sau và ghi đè lên
        // `.idle` bằng một kết quả không còn liên quan gì tới màn hình nữa.
        generation += 1
        guard !trimmed.isEmpty else {
            state = .idle
            return
        }
        lastText = trimmed
        let thisGeneration = generation
        state = .loading(trimmed)
        backend.lookup(trimmed) { [weak self] result in
            guard let self, self.generation == thisGeneration else { return }
            self.state = .done(result)
        }
    }

    /// Đường hotkey: shell capture selection rồi phát ra outcome này.
    public func handle(_ outcome: CaptureOutcome) {
        // Một capture mới xoá picking đang chờ. Popup có thể đã bị ẩn khi
        // picker còn mở; để nguyên thì nó hiện lại đè lên kết quả mới, ở
        // chiều cao đầy đủ, liệt kê ngôn ngữ cho lần tra trước đó.
        picking = nil

        switch outcome {
        case .text(let text):
            query = text
            run(text)
        case .needsPermission:
            // Cùng lý do bump ở đầu `run()` (I-6, final review): một lookup
            // của lần capture TRƯỚC có thể vẫn đang chờ trả lời — completion
            // của nó tới sau nhánh này sẽ ghi `.done(...)` đè lên cổng quyền
            // đang hiện, dù chẳng còn liên quan gì tới nó nữa.
            generation += 1
            state = .needsPermission
        case .empty:
            generation += 1
            state = .idle
            query = ""
        }
    }

    /// Đổi một bên của cặp rồi tra lại cùng chuỗi.
    ///
    /// Chạy lại trên `lastText` đã có, không capture lại: lựa chọn tạo ra kết
    /// quả này đã biến mất khỏi app kia từ lâu, hỏi lại sẽ là một lần tra
    /// khác.
    public func pick(_ side: PickerSide, code: String) {
        picking = nil
        guard let config else { return }

        let source = side == .source ? (code == LanguageNames.auto ? nil : code) : config.source
        let target = side == .target ? code : config.target
        let other = config.other

        // Render thứ backend thực sự lưu — nó sửa xung đột ngôn ngữ, nên một
        // cập nhật lạc quan phía UI có thể bất đồng với nó.
        guard let stored = backend.setLangConfig(source: source, target: target, other: other) else { return }
        self.config = stored
        if !lastText.isEmpty {
            run(lastText)
        }
    }

    /// Trả `true` nếu đã tiêu thụ phím (đóng picker). Quyết định theo
    /// `pickerOpen`, không theo `picking` — một lần bấm không được bị nuốt để
    /// đóng thứ vô hình.
    @discardableResult
    public func escape() -> Bool {
        guard pickerOpen else { return false }
        picking = nil
        return true
    }

    /// Gọi khi popup bị đóng mà KHÔNG đi qua `handle(_:)` — bấm Escape trong
    /// lúc cổng quyền hiện (RootView), hoặc bấm hotkey lần nữa để toggle-đóng
    /// (`TranslateController`, Task 18) — chứ không phải một capture mới.
    ///
    /// `.needsPermission` là trạng thái DUY NHẤT giữ một tài nguyên sống:
    /// `PermissionGateView` poll `hasAccessibility()` bằng `Timer` và chỉ
    /// dừng nó ở `onGranted` hoặc `onDisappear`. Panel là một `NSPanel` sống
    /// suốt vòng đời app với `contentView` gán một lần — `onDisappear` CHỈ
    /// bắn khi view thật sự bị gỡ khỏi cây SwiftUI, tức là khi `state` đổi
    /// khỏi `.needsPermission`, không phải khi panel chỉ `orderOut()`. Không
    /// gọi hàm này ở đúng thời điểm popup đóng thì timer poll (2 lần/giây)
    /// chạy vĩnh viễn dù popup đã ẩn — app nằm ở tray nhiều ngày liền nên đó
    /// là tiêu pin thật, không phải lý thuyết. Bản React gốc không có bước
    /// này (`hidePopup()` không reset state) vì trình duyệt tự throttle timer
    /// nền; `Timer` của Swift thì không — port trung thực ở đây sẽ khuếch đại
    /// một khiếm khuyết môi trường cũ che bớt, nên đây là chỗ cố ý không port
    /// 1:1.
    ///
    /// Vô hại ở mọi trạng thái khác — không có tài nguyên nào khác cần giải
    /// phóng, nên gọi hàm này một cách bảo thủ (mọi lần Escape, mọi lần
    /// toggle-đóng) là an toàn.
    public func dismissed() {
        guard case .needsPermission = state else { return }
        state = .idle
    }
}
