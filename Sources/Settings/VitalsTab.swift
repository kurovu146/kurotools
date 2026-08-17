import SwiftUI
import Vitals

/// Tab thứ ba: ngưỡng quá nhiệt, nhịp làm mới, và những dòng hiện trong menu.
///
/// Mọi thay đổi đi qua `model.applyVitals` → `VitalsController.apply` — đường
/// DUY NHẤT cập nhật đủ ba nơi (bản sao trong bộ nhớ, `UserDefaults`, và
/// ngưỡng riêng của `FanController`). Ghi thẳng preference từ đây sẽ để lại
/// một UI báo đã đổi trong khi quạt vẫn chạy theo ngưỡng cũ.
public struct VitalsTab: View {
    @ObservedObject var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Stepper(value: binding(\.thresholdC), in: 80...105, step: 1) {
                    Text("Ngưỡng quá nhiệt: \(Int(model.vitalsSettings().thresholdC))°C")
                        .font(.system(size: 13))
                }
                .frame(maxWidth: 320, alignment: .leading)
                Text("Quá ngưỡng này, quạt đang đặt tay sẽ được trả về Auto.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Nhịp làm mới: \(refreshLabel)")
                    .font(.system(size: 13))
                // `step: 0.5` không chỉ để chia nấc: nó giới hạn số lần
                // `applyVitals` bắn ra trong một cú kéo — mỗi lần gọi ghi
                // `UserDefaults` và lên lịch lại `Timer`.
                Slider(value: binding(\.refreshSeconds), in: 0.5...5, step: 0.5)
                    .frame(maxWidth: 320)
                Text("Menu chỉ đọc cảm biến khi đang mở hoặc khi có quạt đặt tay — nhịp nhanh không tốn pin khi máy rảnh.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Hiện trong menu").font(.system(size: 13, weight: .semibold))
                Toggle("Nhiệt độ", isOn: binding(\.showTemp))
                Toggle("CPU", isOn: binding(\.showCPU))
                Toggle("RAM", isOn: binding(\.showRAM))
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var refreshLabel: String {
        String(format: "%.1f giây", model.vitalsSettings().refreshSeconds)
    }

    /// Đọc từ controller, ghi qua `applyVitals`. Không có bản sao `@State` nào
    /// ở tab này: một bản sao như thế sẽ trôi khỏi giá trị controller thật sự
    /// đang chạy ngay khi có nơi khác đổi preference (menu bar cũng đổi được).
    private func binding<Value>(
        _ keyPath: WritableKeyPath<Vitals.Settings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.vitalsSettings()[keyPath: keyPath] },
            set: { newValue in
                var next = model.vitalsSettings()
                next[keyPath: keyPath] = newValue
                model.applyVitals(next)
            })
    }
}
