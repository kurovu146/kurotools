import Foundation

/// Cấu hình "hình nền video" của APP. Chỉ app đọc/ghi nó.
///
/// KHÔNG dùng file này để nói chuyện với screensaver. Screensaver bên thứ ba
/// chạy trong `legacyScreenSaver` và BỊ SANDBOX: đo trên máy 2026-08-29, cùng
/// một suite name cho ra hai file plist khác nhau —
/// `~/Library/Preferences/com.kurovu146.kurotools.wallpaper.plist` của app và
/// một bản riêng trong `~/Library/Containers/…legacyScreenSaver/Data/…`. Cây
/// cầu sang screensaver là một FILE VIDEO trong container, xem
/// `SaverVideoInstaller` / `SaverVideoLocator`.
public struct WallpaperSettings: Equatable {
    public var videoURL: URL?
    public var enabled: Bool

    public init(videoURL: URL? = nil, enabled: Bool = false) {
        self.videoURL = videoURL
        self.enabled = enabled
    }
}

/// Lưu/đọc `WallpaperSettings` trên đĩa. Tách khỏi controller để test được
/// round-trip mà không cần dựng cửa sổ/AVPlayer nào.
public final class WallpaperSettingsStore {
    public static let suiteName = "com.kurovu146.kurotools.wallpaper"
    public static let videoPathKey = "videoPath"
    public static let enabledKey = "enabled"

    private let defaults: UserDefaults

    /// `defaults` là seam cho test; production dùng suite RIÊNG của app —
    /// screensaver bị sandbox nên không đọc được nó, xem chú thích đầu file.
    /// `?? .standard` phòng ca suite nil (không xảy ra ở đây).
    public init(defaults: UserDefaults = UserDefaults(suiteName: WallpaperSettingsStore.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    public func load() -> WallpaperSettings {
        var settings = WallpaperSettings()
        if let path = defaults.string(forKey: Self.videoPathKey), !path.isEmpty {
            settings.videoURL = URL(fileURLWithPath: path)
        }
        settings.enabled = defaults.bool(forKey: Self.enabledKey)
        return settings
    }

    public func save(_ settings: WallpaperSettings) {
        defaults.set(settings.videoURL?.path, forKey: Self.videoPathKey)
        defaults.set(settings.enabled, forKey: Self.enabledKey)
    }
}
