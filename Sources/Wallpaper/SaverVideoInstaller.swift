import Foundation

/// Đường dẫn tới chỗ screensaver đọc video.
///
/// Screensaver bên thứ ba chạy trong `legacyScreenSaver` và BỊ SANDBOX — đo
/// trên máy 2026-08-29: cùng một suite `UserDefaults` cho ra hai file plist
/// khác nhau, một ở `~/Library/Preferences`, một trong container. Nên cây cầu
/// giữa hai tiến trình không thể là preferences; nó là một file video nằm sẵn
/// trong container, chỗ duy nhất sandbox chắc chắn cho saver đọc.
public enum SaverVideoPaths {
    public static let containerID = "com.apple.ScreenSaver.Engine.legacyScreenSaver"
    public static let folderName = "KuroTools"
    public static let baseName = "screensaver-video"

    /// App KHÔNG sandbox nên phải tự dựng đường dẫn container tuyệt đối.
    /// (Saver thì ngược lại — xem `SaverVideoLocator`.)
    public static func containerAppSupport(home: URL) -> URL {
        home
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(containerID)
            .appendingPathComponent("Data/Library/Application Support")
            .appendingPathComponent(folderName)
    }

    public static func defaultFolder() -> URL {
        containerAppSupport(home: URL(fileURLWithPath: NSHomeDirectory()))
    }
}

public enum SaverVideoInstallError: Error, Equatable {
    case sourceMissing(URL)
}

/// Seam cho `SettingsModel`: test không được copy gì vào container thật.
public protocol SaverVideoInstalling: Sendable {
    @discardableResult
    func install(_ source: URL) throws -> URL
    func clear() throws
}

/// Installer không làm gì, dành cho test không quan tâm tới cây cầu sang
/// screensaver. Tồn tại để `SettingsModel` KHÔNG bao giờ phải rơi về
/// `SaverVideoInstaller()` mặc định: cái đó trỏ vào container THẬT, và một test
/// gọi `setWallpaperVideo` với đường dẫn scratch tình cờ tồn tại sẽ xoá video
/// screensaver thật của người dùng. Cùng lý do với `NoopWallpaper`.
public struct NoopSaverInstaller: SaverVideoInstalling {
    public init() {}

    @discardableResult
    public func install(_ source: URL) throws -> URL { source }
    public func clear() throws {}
}

/// Chỉ giữ một `URL` nên nó `Sendable` tự nhiên — quan trọng, vì `SettingsModel`
/// đẩy `install` sang thread nền (video vài trăm MB không được chặn UI).
/// `FileManager` dựng mới trong từng hàm theo khuyến nghị của Apple cho code
/// chạy ngoài main thread.
public struct SaverVideoInstaller: SaverVideoInstalling {
    public let folder: URL

    public init(folder: URL = SaverVideoPaths.defaultFolder()) {
        self.folder = folder
    }

    @discardableResult
    public func install(_ source: URL) throws -> URL {
        let fm = FileManager()
        // Kiểm tra TRƯỚC khi tạo thư mục: nguồn hỏng không được để lại dấu vết.
        guard fm.fileExists(atPath: source.path) else {
            throw SaverVideoInstallError.sourceMissing(source)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try removeInstalled(fm)

        let ext = source.pathExtension
        let name = ext.isEmpty
            ? SaverVideoPaths.baseName
            : "\(SaverVideoPaths.baseName).\(ext)"
        let destination = folder.appendingPathComponent(name)
        try fm.copyItem(at: source, to: destination)
        return destination
    }

    public func clear() throws {
        try removeInstalled(FileManager())
    }

    public func installedVideo() -> URL? {
        let fm = FileManager()
        guard let items = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil) else { return nil }
        return items.first { $0.deletingPathExtension().lastPathComponent == SaverVideoPaths.baseName }
    }

    /// Xoá MỌI `screensaver-video.*`, không chỉ đuôi đang cài: đổi từ `.mov`
    /// sang `.mp4` mà chỉ ghi đè theo tên đầy đủ sẽ để lại hai file.
    private func removeInstalled(_ fm: FileManager) throws {
        guard let items = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil) else { return }
        for item in items
        where item.deletingPathExtension().lastPathComponent == SaverVideoPaths.baseName {
            try fm.removeItem(at: item)
        }
    }
}
