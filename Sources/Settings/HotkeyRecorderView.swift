import AppKit
import Carbon.HIToolbox
import SwiftUI
import Translate

/// Chuyển một sự kiện phím của Cocoa thành tổ hợp Carbon mà
/// `RegisterEventHotKey` hiểu. Tách thành hàm thuần để test được mà không
/// cần dựng cửa sổ thật.
public enum HotkeyRecorder {
    public static func combo(
        fromCarbonKeyCode keyCode: UInt32, cocoaModifiers: NSEvent.ModifierFlags
    ) -> HotkeyCombo? {
        var carbon: UInt32 = 0
        if cocoaModifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaModifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if cocoaModifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaModifiers.contains(.control) { carbon |= UInt32(controlKey) }
        guard carbon != 0 else { return nil }
        return HotkeyCombo(keyCode: keyCode, modifiers: carbon)
    }
}

/// Ô bấm để ghi phím tắt. Khi đang ghi, mọi phím gõ vào đều bị nuốt.
public struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var combo: HotkeyCombo
    let onRecorded: (HotkeyCombo) -> Void

    public init(combo: Binding<HotkeyCombo>, onRecorded: @escaping (HotkeyCombo) -> Void) {
        self._combo = combo
        self.onRecorded = onRecorded
    }

    public func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.onRecorded = { recorded in
            combo = recorded
            onRecorded(recorded)
        }
        field.combo = combo
        return field
    }

    public func updateNSView(_ view: RecorderField, context: Context) {
        view.combo = combo
    }
}

public final class RecorderField: NSButton {
    var onRecorded: ((HotkeyCombo) -> Void)?
    var isRecording = false { didSet { refreshTitle() } }
    var combo: HotkeyCombo = .default { didSet { refreshTitle() } }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var acceptsFirstResponder: Bool { true }

    @objc private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    private func refreshTitle() {
        title = isRecording ? "Bấm tổ hợp phím…" : combo.displayString
    }

    public override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            return
        }
        guard let recorded = HotkeyRecorder.combo(
            fromCarbonKeyCode: UInt32(event.keyCode),
            cocoaModifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        else { return }   // thiếu modifier: tiếp tục chờ, không đóng ô ghi
        isRecording = false
        combo = recorded
        onRecorded?(recorded)
    }
}
