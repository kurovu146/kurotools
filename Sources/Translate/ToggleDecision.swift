/// Việc `toggle()` (`TranslateController.swift`) nên làm — tách khỏi mọi
/// state AppKit thật (`NSPanel`, `HotkeyMonitor`) để test được mà không cần
/// dựng chúng. Cùng khuôn `measuredHeight` (PanelSizing.swift): một hàm thuần
/// đứng cạnh code AppKit nó phục vụ, thay vì chôn logic quyết định bên trong
/// một class không test được.
public enum ToggleDecision: Equatable {
    case ignore
    case show
    case hide
}

/// `isCapturing`: có một `captureAsync` đang bay hay không (I-1 follow-up,
/// final review). Panel chỉ `show()` BÊN TRONG completion của nó, nên
/// `isPanelVisible` luôn `false` suốt khoảng chờ đó — thiếu nhánh này, một
/// lần bấm hotkey thứ hai trong cửa sổ ~1.4s (COPY_TIMEOUT + LATE_WRITE_GRACE
/// trên đường capture thất bại) sẽ luôn đọc ra `.show`, bắn thêm một lần
/// capture chồng lên lần đang chạy thay vì coi đó là một request trùng lặp.
public func decideToggle(isCapturing: Bool, isPanelVisible: Bool) -> ToggleDecision {
    guard !isCapturing else { return .ignore }
    return isPanelVisible ? .hide : .show
}
