import Foundation

/// Cấu hình "hình nền video" + screensaver video, dùng chung giữa app và
/// screensaver bundle.
///
/// Hai tiến trình KHÁC NHAU đọc nó: `KuroTools.app` (người ghi) và
/// `KuroToolsWallpaper.saver` chạy trong ScreenSaverEngine (người đọc). Cả hai
/// đều không sandbox, nên một `UserDefaults(suiteName:)` bình thường — tức một
/// file plist trong `~/Library/Preferences` — là đủ; không cần app group.
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

    /// `defaults` là seam cho test; production dùng suite dùng chung với
    /// screensaver. `?? .standard` phòng ca suite nil (không xảy ra ở đây).
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
