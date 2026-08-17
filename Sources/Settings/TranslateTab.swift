import SwiftUI
import Translate

/// Tab thứ hai: cặp ngôn ngữ. Ba lựa chọn này là thứ DUY NHẤT của KTranslate
/// còn phải cấu hình bằng tay.
///
/// Không giữ `@State` nào: danh sách ngôn ngữ và cấu hình hiện tại nằm trong
/// model, nạp lại mỗi lần cửa sổ hiện (`refreshFromSystem`). Một bản sao cục
/// bộ ở đây sẽ đứng yên sau khi người dùng đổi ngôn ngữ ngay trong popup tra
/// từ, hoặc sau khi db bị đổi chỗ/xoá sạch — và `.onAppear` không cứu được vì
/// nó chỉ chạy một lần cho cả vòng đời app.
public struct TranslateTab: View {
    @ObservedObject var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.langConfig == nil {
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
        .disabled(model.langConfig == nil)
        .frame(maxWidth: 320)
    }

    /// Ngôn ngữ dùng gần đây lên trước, phần còn lại theo tên hiển thị — cùng
    /// thứ tự `LanguagePickerView` dùng trong popup, để hai chỗ không xếp
    /// khác nhau cho cùng một danh sách.
    private func ordered() -> [String] {
        let known = Set(model.languages)
        let validRecent = model.recentLanguages.filter { known.contains($0) }
        let rest = model.languages
            .filter { !Set(validRecent).contains($0) }
            .sorted { LanguageNames.name($0) < LanguageNames.name($1) }
        return validRecent + rest
    }

    // MARK: - Ghi qua model, đọc lại thứ backend TRẢ VỀ

    private var sourceBinding: Binding<String> {
        Binding(
            get: { model.langConfig?.source ?? LanguageNames.auto },
            set: { save(source: $0, target: model.langConfig?.target, other: model.langConfig?.other) })
    }

    private var targetBinding: Binding<String> {
        Binding(
            get: { model.langConfig?.target ?? "" },
            set: { save(source: currentSource, target: $0, other: model.langConfig?.other) })
    }

    private var otherBinding: Binding<String> {
        Binding(
            get: { model.langConfig?.other ?? "" },
            set: { save(source: currentSource, target: model.langConfig?.target, other: $0) })
    }

    private var currentSource: String { model.langConfig?.source ?? LanguageNames.auto }

    private func save(source: String, target: String?, other: String?) {
        guard let target, let other else { return }
        let normalized = source == LanguageNames.auto ? nil : source
        // `model.setLangConfig` tự cập nhật `langConfig` bằng thứ backend
        // THỰC SỰ lưu (`LangConfig::new` phía Rust sửa va chạm), nên picker
        // hiện giá trị đã lưu chứ không phải giá trị vừa chọn.
        model.setLangConfig(source: normalized, target: target, other: other)
    }
}
