import Foundation

/// Phía screensaver của cây cầu. Chạy TRONG sandbox của `legacyScreenSaver`,
/// nên `applicationSupportDirectory` đã tự trỏ vào container — saver không cần
/// biết chữ "Containers" nào cả. Công thức này phải cho ra đúng thư mục mà
/// `SaverVideoPaths.containerAppSupport(home:)` bên app trỏ tới;
/// `SaverVideoLocatorTests` là thứ giữ hai bên khớp nhau.
public enum SaverVideoLocator {
    public static let folderName = "KuroTools"
    public static let baseName = "screensaver-video"

    public static func folder(inApplicationSupport base: URL) -> URL {
        base.appendingPathComponent(folderName)
    }

    public static func find(inApplicationSupport base: URL) -> URL? {
        let fm = FileManager()
        guard let items = try? fm.contentsOfDirectory(
            at: folder(inApplicationSupport: base), includingPropertiesForKeys: nil)
        else { return nil }
        return items.first { $0.deletingPathExtension().lastPathComponent == baseName }
    }

    public static func findInDefaultLocation() -> URL? {
        guard let base = FileManager()
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return find(inApplicationSupport: base)
    }
}
