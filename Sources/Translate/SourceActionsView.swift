import SwiftUI

/// Model của hai nút lưu từ / phát âm cạnh headword. Port từ
/// `~/Dev/ktranslate/src/components/SourceActions.tsx`.
///
/// Cả hai best-effort: một lần ghi hỏng hay thiếu bộ tổng hợp giọng nói không
/// được làm sập panel đang hiện bản dịch — không có `try/catch` nào bung lên
/// UI, mọi thất bại chỉ lặng lẽ trả nút về trạng thái cũ.
@MainActor
public final class SourceActionsModel: ObservableObject {
    private let backend: TranslateBackend

    @Published public var saved: Bool = false
    @Published public var canSpeak: Bool = false

    /// Token thế hệ: tăng mỗi lần `load`. Người dùng có thể tra từ thứ hai
    /// trước khi `isSavedAsync` của từ đầu trả lời — không có bảo vệ này,
    /// câu trả lời CŨ (về sau) sẽ ghi đè câu trả lời MỚI đã tới trước nó.
    /// Không so bằng chuỗi `text`: hai lần tra liên tiếp có thể trùng chữ.
    private var generation = 0

    public init(backend: TranslateBackend) {
        self.backend = backend
        // Gate nút loa theo khả năng THẬT thay vì giả định — máy có thể
        // không có bộ tổng hợp giọng nói cài sẵn, và một nút im lặng không
        // làm gì còn tệ hơn không có nút.
        canSpeak = backend.ttsAvailable()
    }

    /// Hỏi lại trạng thái lưu cho `text` mới. Gọi ở cả mount lẫn mỗi lần
    /// headword đổi (xem `LookupResultView.onAppear`/`onChange`).
    public func load(text: String) {
        generation += 1
        let thisGeneration = generation
        backend.isSavedAsync(text) { [weak self] value in
            guard let self, self.generation == thisGeneration else { return }
            self.saved = value
        }
    }

    /// Optimistic: nút phải cảm giác tức thì, nên `saved` đổi ngay trước khi
    /// biết ghi có thành công không. Rollback khi hỏng — một lần ghi không
    /// xảy ra không được trông như đã xảy ra.
    public func toggleSave(text: String) {
        let next = !saved
        saved = next
        if !backend.setSaved(text, saved: next) {
            saved = !next
        }
    }

    public func speak(text: String) {
        backend.speak(text)
    }
}

/// Hai nút lưu từ / phát âm, xếp cạnh headword.
public struct SourceActionsView: View {
    let text: String
    @ObservedObject var model: SourceActionsModel

    public init(text: String, model: SourceActionsModel) {
        self.text = text
        self.model = model
    }

    public var body: some View {
        // shrink-0 kiểu SwiftUI: đặt trong HStack riêng và không cho co giãn,
        // để một headword dài không ép hàng nút này ra ngoài panel.
        HStack(spacing: 2) {
            if model.canSpeak {
                IconActionButton(
                    systemName: "speaker.wave.2",
                    label: "Pronounce",
                    active: false,
                    action: { model.speak(text: text) })
            }
            IconActionButton(
                systemName: model.saved ? "star.fill" : "star",
                label: model.saved ? "Remove from saved words" : "Save this word",
                active: model.saved,
                action: { model.toggleSave(text: text) })
        }
        .fixedSize()
        .padding(.top, 2)
    }
}

/// Ô bấm vuông 24pt cho một glyph SF Symbol — tương đương `IconButton` của
/// bản TS, dùng SF Symbol hệ thống thay vì SVG tay vẽ (speaker/star đã có
/// sẵn glyph chuẩn của macOS).
///
/// Mờ tới khi hover: hai nút này đứng cạnh headword, để sáng hẳn thì chúng
/// tranh sự chú ý với chính chữ đang được tra.
private struct IconActionButton: View {
    /// Tương đương "amber-500" của Tailwind trong bản TS — màu ngôi sao khi
    /// đã lưu, giữ nguyên để nhất quán thị giác với `tl`/ktranslate.
    private static let activeColor = Color(red: 0.961, green: 0.620, blue: 0.043)

    let systemName: String
    let label: String
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundColor(active ? Self.activeColor : (hovering ? .primary : .secondary))
        .background(hovering ? Color.primary.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help(label)
        .accessibilityLabel(label)
        // Tương đương `aria-pressed={pressed}` của bản TS trên nút lưu: VoiceOver
        // phải nghe được nút đang ở trạng thái đã lưu hay chưa, không chỉ thấy màu
        // đổi. `active` trùng đúng ý nghĩa "đang bật" cho cả hai lần gọi hiện tại
        // (loa luôn `false` — không phải nút toggle; sao là `saved`), nên dùng
        // thẳng nó thay vì thêm một tham số riêng.
        .accessibilityAddTraits(active ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}
