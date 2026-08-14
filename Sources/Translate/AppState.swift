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
        guard !trimmed.isEmpty else {
            state = .idle
            return
        }
        lastText = trimmed
        state = .loading(trimmed)
        backend.lookup(trimmed) { [weak self] result in
            self?.state = .done(result)
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
            state = .needsPermission
        case .empty:
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
}
