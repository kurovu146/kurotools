import SwiftUI

/// Bố cục kết quả tra, giống panel Look Up của macOS: chữ được tra ở trên
/// cùng với senses bên dưới, một hairline, rồi bản dịch dưới cặp ngôn ngữ đã
/// tạo ra nó. Port từ `~/Dev/ktranslate/src/components/LookupView.tsx` +
/// `primitives.tsx` — không box/border/header kẻ vạch, chỉ một hairline duy
/// nhất ngăn từ điển với bản dịch.
///
/// Hai bất biến mang từ `tl` sang, đều load-bearing:
/// - Senses **biến mất hoàn toàn** khi rỗng — một khối có nhãn mà rỗng là
///   nhiễu, không phải thông tin.
/// - Bản dịch **LUÔN render**, hiện "unavailable" khi không có — đây là khối
///   mà công cụ tồn tại vì nó, sự vắng mặt phải được NÓI RA chứ không suy ra
///   từ một khoảng trống.
public struct LookupResultView: View {
    private static let maxChars = 5000

    let result: Lookup
    /// Ngôn ngữ nguồn được ĐOÁN, không phải cấu hình — xem `PairButton`.
    let sourceDetected: Bool
    let onPickSource: () -> Void
    let onPickTarget: () -> Void

    /// Panel này SỞ HỮU model của các nút lưu/phát âm — không có nơi nào
    /// khác trong app cần biết về `SourceActionsModel`, và nó phải sống lâu
    /// bằng đúng result đang hiện để token thế hệ của nó theo dõi được các
    /// lần tra kế tiếp (xem `onChange` bên dưới + `SourceActionsModel`).
    @StateObject private var actions: SourceActionsModel

    public init(result: Lookup, sourceDetected: Bool, backend: TranslateBackend,
                onPickSource: @escaping () -> Void, onPickTarget: @escaping () -> Void) {
        self.result = result
        self.sourceDetected = sourceDetected
        self.onPickSource = onPickSource
        self.onPickTarget = onPickTarget
        _actions = StateObject(wrappedValue: SourceActionsModel(backend: backend))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Headword(text: result.source)
                SourceActionsView(text: result.source, model: actions)
            }

            if !result.partOfSpeechLine.isEmpty {
                Text(result.partOfSpeechLine)
                    .font(.system(size: 12))
                    .italic()
                    // `.foregroundColor`, không phải `.foregroundStyle`: gọi
                    // trực tiếp trên một `Text` (không phải trên View bao
                    // ngoài), `.foregroundStyle` khớp overload CHỈ Text mới có
                    // từ macOS 14 — vỡ build trên target macOS 13 của package
                    // này (đã đo). `.foregroundColor` tương thích cả hai.
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

            // Senses và bản dịch giữ con trỏ để bôi đen/copy — hàng headword
            // phía trên CỐ Ý không có `.textSelection`: nó là tay cầm kéo
            // panel (`DraggableHostingView.mouseDown`), và chữ ở đó vốn đã
            // được chọn sẵn trong app nó đến từ.
            if !result.definitions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(result.definitions.enumerated()), id: \.offset) { i, d in
                        SenseRow(index: i + 1, definition: d)
                    }
                }
                .padding(.top, 6)
                .textSelection(.enabled)
            }

            if result.sourceTruncated {
                Text("… truncated at \(Self.maxChars.formatted()) characters — only that much was sent")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .padding(.top, 6)
            }

            // SwiftUI's own `Divider` đã đúng thứ mô tả cần — một hairline hệ
            // thống tự đổi màu theo giao diện sáng/tối; không cần vẽ tay như
            // bản TS (`bg-rule` tự viết) làm khi không có nó sẵn.
            Divider()
                .padding(.vertical, 10)

            // Nhãn cặp thay cho một label tĩnh "Vietnamese" cũ: `targetLang`
            // là ngôn ngữ THỰC SỰ được dùng, không phải cái đã cấu hình — quy
            // tắc no-op có thể thử lại vào ngôn ngữ dự phòng, và nhãn phải
            // bám theo cái đó.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                PairButton(
                    label: result.sourceLang.map(LanguageNames.name) ?? "Auto",
                    hint: "source",
                    uncertain: sourceDetected,
                    action: onPickSource)
                Text("→").accessibilityHidden(true)
                PairButton(
                    label: LanguageNames.name(result.targetLang),
                    hint: "target",
                    uncertain: false,
                    action: onPickTarget)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            .textCase(.uppercase)
            .padding(.bottom, 4)

            if let translation = result.translation {
                Text(translation)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
            } else {
                Text("unavailable")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundColor(.secondary)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        // Chạy lúc mount VÀ mỗi lần `source` đổi — cùng cặp dependency mà
        // `useEffect(() => ..., [text])` phủ ở bản TS (effect chạy ở mount
        // lẫn khi dependency đổi). `SourceActionsModel` tự bảo vệ khỏi việc
        // một lần tra CŨ ghi đè lần tra MỚI bằng token thế hệ, nên gọi lại vô
        // hại kể cả khi cả hai fire gần nhau lúc panel vừa hiện.
        .onAppear { actions.load(text: result.source) }
        .onChange(of: result.source) { newValue in actions.load(text: newValue) }
    }
}

/// Chữ được tra. Một từ đơn lấy cỡ chữ lớn kiểu Look Up hệ thống; một câu ở
/// cỡ đó sẽ lấp đầy panel trước khi bản dịch — thứ thực sự cần — có được một
/// dòng, nên nó lùi về cỡ chữ thường.
private struct Headword: View {
    /// Dài hơn mức này thì `text` là một cụm, không phải một từ.
    private static let maxWordChars = 28

    let text: String

    var body: some View {
        let isWord = text.count <= Self.maxWordChars && !text.contains("\n")
        Text(text)
            .font(isWord ? .system(size: 21, weight: .semibold) : .system(size: 14))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Một sense đánh số. `.monospacedDigit()` giữ các chữ số cùng độ rộng để
/// gloss của sense 1 tới 10 đều bắt đầu thẳng cột.
private struct SenseRow: View {
    let index: Int
    let definition: Definition

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .monospacedDigit()
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            (
                (definition.domain.map { Text("\($0) ").italic().foregroundColor(.secondary) } ?? Text(""))
                + Text(definition.gloss)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
    }
}

/// Một nửa của cặp ngôn ngữ — click target không trông giống nút bấm.
private struct PairButton: View {
    let label: String
    /// Bên nào của cặp, dùng cho tooltip/accessibility label.
    let hint: String
    /// Ngôn ngữ được ĐOÁN thì in nghiêng — cùng cách mọi chuỗi kém chắc chắn
    /// khác trong panel này (nhãn domain, ghi chú truncate, "unavailable").
    let uncertain: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let title = "Change the \(hint) language — currently \(label)"
        Button(action: action) {
            Text(label)
                .italic(uncertain)
                .padding(.horizontal, 2)
                .background(hovering ? Color.primary.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering = $0 }
    }
}
