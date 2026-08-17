import SwiftUI
import Translate

/// Tab thứ hai: cặp ngôn ngữ. Ba lựa chọn này là thứ DUY NHẤT của KTranslate
/// còn phải cấu hình bằng tay.
public struct TranslateTab: View {
    @ObservedObject var model: SettingsModel

    /// Nạp một lần trong `onAppear`, không đọc trong `body`: `languages()` đi
    /// qua FFI rồi giải mã JSON 133 mã ngôn ngữ, và `body` chạy lại mỗi lần
    /// bất kỳ `@Published` nào của model đổi.
    @State private var languages: [String] = []
    @State private var recent: [String] = []
    /// Cấu hình mà BACKEND đang giữ — không phải thứ vừa được chọn.
    @State private var config: LangConfig?

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if config == nil {
                Text("Không đọc được cấu hình ngôn ngữ từ db.")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }

            picker("Ngôn ngữ nguồn", selection: sourceBinding, includeAuto: true)
            picker("Dịch sang", selection: targetBinding, includeAuto: false)
            picker("Ngôn ngữ phụ", selection: otherBinding, includeAuto: false)

            Text("""
            Ngôn ngữ phụ là đích dự phòng: khi văn bản đã ở đúng ngôn ngữ đích, \
            bản dịch sẽ chạy sang ngôn ngữ này thay vì trả lại y nguyên.
            """)
            .font(.system(size: 11))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            languages = model.languages()
            recent = model.recentLanguages()
            config = model.langConfig()
        }
    }

    private func picker(_ title: String, selection: Binding<String>, includeAuto: Bool) -> some View {
        Picker(title, selection: selection) {
            if includeAuto {
                Text("Tự nhận").tag(LanguageNames.auto)
            }
            ForEach(ordered(), id: \.self) { code in
                Text(LanguageNames.name(code)).tag(code)
            }
        }
        .disabled(config == nil)
        .frame(maxWidth: 320)
    }

    /// Ngôn ngữ dùng gần đây lên trước, phần còn lại theo tên hiển thị — cùng
    /// thứ tự `LanguagePickerView` dùng trong popup, để hai chỗ không xếp
    /// khác nhau cho cùng một danh sách.
    private func ordered() -> [String] {
        let known = Set(languages)
        let validRecent = recent.filter { known.contains($0) }
        let rest = languages
            .filter { !Set(validRecent).contains($0) }
            .sorted { LanguageNames.name($0) < LanguageNames.name($1) }
        return validRecent + rest
    }

    // MARK: - Ghi qua backend, đọc lại thứ nó TRẢ VỀ

    private var sourceBinding: Binding<String> {
        Binding(
            get: { config?.source ?? LanguageNames.auto },
            set: { save(source: $0, target: config?.target, other: config?.other) })
    }

    private var targetBinding: Binding<String> {
        Binding(
            get: { config?.target ?? "" },
            set: { save(source: config?.source ?? LanguageNames.auto, target: $0, other: config?.other) })
    }

    private var otherBinding: Binding<String> {
        Binding(
            get: { config?.other ?? "" },
            set: { save(source: config?.source ?? LanguageNames.auto, target: config?.target, other: $0) })
    }

    /// Hiển thị lại giá trị BACKEND trả về, không phải giá trị vừa chọn:
    /// `LangConfig::new` phía Rust sửa va chạm (đích trùng nguồn, phụ trùng
    /// đích…), nên hai thứ có thể khác nhau — và cái đúng là cái đã lưu.
    private func save(source: String, target: String?, other: String?) {
        guard let target, let other else { return }
        let normalized = source == LanguageNames.auto ? nil : source
        if let saved = model.setLangConfig(source: normalized, target: target, other: other) {
            config = saved
        } else {
            // Lưu hỏng: đọc lại để picker không đứng ở một giá trị chưa bao
            // giờ được ghi. `model.setLangConfig` đã đặt dòng phản hồi.
            config = model.langConfig()
        }
        recent = model.recentLanguages()
    }
}
