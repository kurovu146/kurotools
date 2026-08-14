import SwiftUI

/// Overlay toàn diện tích liệt kê mọi ngôn ngữ, lọc dần khi gõ. Port từ
/// `~/Dev/ktranslate/src/components/LanguagePicker.tsx`.
///
/// View này tự chứa toàn bộ hành vi của picker (lọc, sắp xếp, chọn) nhưng
/// KHÔNG tự quyết định nó xuất hiện Ở ĐÂU trong cây view — đó là việc của nơi
/// gọi nó (`RootView`, Task 17), vì các bất biến dưới đây chỉ thi hành đúng
/// được từ tầng cha:
///
/// 1. **Phải đặt bằng `.overlay()` trên container NGOÀI CÙNG, không phải bên
///    trong cây được đo chiều cao** (`measuredHeight`, PanelSizing.swift).
///    View này cố tình luôn chiếm trọn `.frame(maxWidth: .infinity,
///    maxHeight: .infinity)` — đúng hình dạng một overlay cần — nhưng nếu
///    nơi gọi đặt nó làm CON của phần tử bị đo thay vì `.overlay()` của nó,
///    danh sách hơn trăm ngôn ngữ sẽ đẩy panel phình to mỗi lần picker mở và
///    không bao giờ co lại — đúng lớp bug `measuredHeight` sinh ra để tránh.
/// 2. Chiều cao panel phải giữ NGUYÊN mức đầy đủ trong lúc picker mở —
///    `AppModel.pickerOpen` (AppState.swift) đã là input sẵn có cho quyết
///    định đó; tầng đo chỉ cần đọc cờ này, view ở đây không cần biết gì về nó.
/// 3. Nội dung PHÍA SAU overlay (kết quả tra đang hiện) phải hết tương tác
///    khi picker mở — `.allowsHitTesting(false)` + `.accessibilityHidden(true)`
///    áp cho LỚP NỘI DUNG đó ở tầng cha, không phải cho view này. Bản React
///    dùng `inert` vì overlay là sibling chứ không phải modal dialog thật —
///    thiếu nó, một lần Shift+Tab đưa focus xuống nút phía sau scrim, và
///    Enter ở đó phát âm/lưu một từ từ phía SAU picker.
///
/// Cố ý KHÔNG bắt phím Escape ở đây: overlay này không có focus trap (bất
/// biến 3 đóng đường vòng Shift+Tab bằng cách khác), nên một handler Escape
/// khoanh vùng trong subtree này sẽ ngừng nhận phím ngay khi focus rơi ra
/// ngoài nó. `AppModel.escape()` xử lý ở tầng trên, nơi focus thực sự đang ở
/// — đúng như bản React để App quyết định dismissal, không phải component này.
public struct LanguagePickerView: View {
    let selected: String
    /// Chỉ đúng cho phía **source** — nơi gọi phải truyền `false` cho target.
    let includeAuto: Bool
    let languages: [String]
    let recent: [String]
    let onPick: (String) -> Void

    @State private var filter = ""
    @FocusState private var searchFocused: Bool

    public init(selected: String, includeAuto: Bool, languages: [String], recent: [String],
                onPick: @escaping (String) -> Void) {
        self.selected = selected
        self.includeAuto = includeAuto
        self.languages = languages
        self.recent = recent
        self.onPick = onPick
    }

    /// Recent hợp lệ (còn nằm trong `languages`) trước, rồi phần còn lại theo
    /// alphabet tên hiển thị. Tương đương phép lọc hai bước của bản TS: ở đó
    /// `rest` loại bỏ theo mảng `recent` THÔ chứ không phải bản đã lọc hợp lệ
    /// — nhưng vì `rest` chỉ duyệt trong `languages`, hai cách lọc luôn cho
    /// cùng kết quả (một mã trong `languages` mà cũng nằm trong `recent` thô
    /// thì chắc chắn cũng nằm trong `recent` đã lọc hợp lệ).
    private var ordered: [String] {
        let known = Set(languages)
        let validRecent = recent.filter { known.contains($0) }
        let validRecentSet = Set(validRecent)
        let head = includeAuto ? [LanguageNames.auto] : []
        let rest = languages
            .filter { !validRecentSet.contains($0) }
            .sorted { LanguageNames.name($0) < LanguageNames.name($1) }
        return head + validRecent + rest
    }

    /// Lọc theo cả tên hiển thị lẫn mã thô — gõ "zh" khớp "zh-CN" dù tên hiện
    /// ra là "Chinese (China mainland)".
    private var shown: [String] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return ordered }
        return ordered.filter {
            LanguageNames.name($0).lowercased().contains(needle) || $0.lowercased().contains(needle)
        }
    }

    public var body: some View {
        ZStack {
            // Lớp nền: hứng MỌI click rơi vào vùng trống của overlay (đệm
            // quanh ô tìm kiếm, khoảng trống dưới hàng cuối cùng khi danh
            // sách ngắn) rồi không làm gì cả. Thiếu lớp này, những click đó
            // xuyên qua tới `DraggableHostingView.mouseDown` của panel gốc và
            // kéo cả cửa sổ (xem PanelSizing.swift — AppKit định tuyến click
            // tới subview khớp hit-test đầu tiên; một Color/Rectangle không
            // gesture không tạo subview nào để nhận, nên click rơi tiếp lên
            // view cha). Bản React chặn đúng ca này bằng
            // `onMouseDown={(e) => e.stopPropagation()}` trên chính div
            // overlay: "The panel drags from anywhere; the picker must not
            // move the window." Đặt thành một lớp NỀN riêng dưới đáy ZStack
            // thay vì gắn thẳng lên VStack chứa nội dung: gắn lên đó sẽ tranh
            // gesture với ScrollView/Button bên trong; đặt dưới đáy, nó chỉ
            // nhận được những click không có view nào khác ở trên nhận trước.
            Rectangle()
                .fill(.regularMaterial)
                .contentShape(Rectangle())
                .onTapGesture {}

            VStack(spacing: 0) {
                TextField("Search languages…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .focused($searchFocused)
                    // Enter chọn kết quả đầu. Chỉ gắn ở field: trên một nút
                    // hàng đang được focus, Enter đã tự thành một cú click
                    // của chính nút đó — thêm handler ở đây nữa sẽ chọn kết
                    // quả đầu ĐÈ LÊN cái người dùng vừa thật sự bấm chọn.
                    .onSubmit {
                        if let first = shown.first { onPick(first) }
                    }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown, id: \.self) { code in
                            LanguageRow(code: code, isSelected: code == selected) { onPick(code) }
                        }
                        if shown.isEmpty {
                            Text("No match")
                                .font(.system(size: 13))
                                .italic()
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Autofocus khớp `inputRef.current?.focus()` của bản React — người
        // dùng mở picker để gõ lọc ngay, không phải để bấm vào ô trước.
        .onAppear { searchFocused = true }
    }
}

/// Một hàng ngôn ngữ — tên hiển thị + mã thô, sáng lên khi hover và in đậm
/// khi đang là lựa chọn hiện tại. Cùng khuôn `IconActionButton`
/// (SourceActionsView.swift) / `PairButton` (LookupResultView.swift): hover
/// tự quản bằng `@State` cục bộ vì `ButtonStyle` không phát tín hiệu hover.
private struct LanguageRow: View {
    let code: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LanguageNames.name(code))
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(code)
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            .padding(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}
