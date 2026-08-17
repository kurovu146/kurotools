import Foundation

/// Ba cờ hiển thị, không phải bốn: `showFan` từng tồn tại nhưng KHÔNG nơi nào
/// đọc (`MenuBarController` chỉ dựng ba mục Show Temp/CPU/RAM), nên nó chỉ là
/// một khoá `save()` vẫn ghi xuống đĩa mãi mãi và một công tắc không làm gì
/// nếu ai đó đưa nó lên UI.
public struct Settings {
    public var showTemp = true
    public var showCPU = true
    public var showRAM = true
    public var thresholdC: Double = 95
    public var refreshSeconds: Double = 1.5
    public init() {}

    private static let defaultValues: [String: Any] = [
        "showTemp": true, "showCPU": true, "showRAM": true,
        "thresholdC": 95.0, "refreshSeconds": 1.5,
    ]

    /// `defaults` defaults to `.standard` for production; tests inject their
    /// own `UserDefaults(suiteName:)` sandbox so they never touch the real
    /// preferences on disk (same pattern as `HotkeyPreference.load`).
    public static func load(defaults: UserDefaults = .standard) -> Settings {
        defaults.register(defaults: defaultValues)
        var s = Settings()
        s.showTemp = defaults.bool(forKey: "showTemp"); s.showCPU = defaults.bool(forKey: "showCPU")
        s.showRAM = defaults.bool(forKey: "showRAM")
        s.thresholdC = defaults.double(forKey: "thresholdC"); s.refreshSeconds = defaults.double(forKey: "refreshSeconds")
        return s
    }
    public func save(defaults: UserDefaults = .standard) {
        defaults.set(showTemp, forKey: "showTemp")
        defaults.set(showCPU, forKey: "showCPU")
        defaults.set(showRAM, forKey: "showRAM")
        defaults.set(thresholdC, forKey: "thresholdC")
        defaults.set(refreshSeconds, forKey: "refreshSeconds")
    }
}
