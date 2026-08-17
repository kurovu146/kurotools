import Foundation

/// Kết luận về một thư mục được chọn làm chỗ chứa db.
public enum LocationVerdict: Equatable {
    case ok
    case notLocalVolume
    case cloudSynced(String)
}

/// SQLite hỏng thật trên hai loại chỗ: ổ mạng (file locking không đáng tin)
/// và thư mục cloud sync (hai máy ghi đè nhau). Cổng này chặn cả hai, và
/// tầng thứ hai mới là tầng khó — thư mục cloud NẰM TRÊN ổ local, nên
/// `volumeIsLocalKey` một mình không bao giờ thấy chúng.
public enum LocalVolumeCheck {
    /// Tiền tố tính từ home, kèm tên dịch vụ để báo cho người dùng.
    private static let cloudPrefixes: [(components: [String], service: String)] = [
        (["Library", "Mobile Documents"], "iCloud Drive"),
        (["Dropbox"], "Dropbox"),
        (["Google Drive"], "Google Drive"),
        (["OneDrive"], "OneDrive"),
    ]

    /// Thư mục con của `~/Library/CloudStorage` mang tên nhà cung cấp, có thể
    /// kèm hậu tố tài khoản (`GoogleDrive-a@b.com`, `OneDrive-Personal`).
    private static let cloudStorageProviders: [(prefix: String, service: String)] = [
        ("Dropbox", "Dropbox"),
        ("GoogleDrive", "Google Drive"),
        ("OneDrive", "OneDrive"),
        ("iCloudDrive", "iCloud Drive"),
        ("Box", "Box"),
    ]

    public static func verdict(
        for url: URL, home: URL, isLocalVolume: (URL) -> Bool?
    ) -> LocationVerdict {
        // Symlink phải được gỡ TRƯỚC khi so tiền tố: máy này có symlink thật
        // (`~/Dev/kurovitals` → `~/Dev/kurotools`), và một symlink trỏ vào
        // Dropbox sẽ lọt qua mọi phép so chuỗi trên đường dẫn chưa resolve.
        let path = url.resolvingSymlinksInPath().standardizedFileURL
        let homePath = home.resolvingSymlinksInPath().standardizedFileURL

        guard isLocalVolume(path) == true else { return .notLocalVolume }

        let parts = path.pathComponents
        let homeParts = homePath.pathComponents
        guard parts.count > homeParts.count, Array(parts.prefix(homeParts.count)) == homeParts
        else { return .ok }
        let relative = Array(parts.dropFirst(homeParts.count))

        if relative.count >= 2, relative[0] == "Library", relative[1] == "CloudStorage" {
            let leaf = relative.count >= 3 ? relative[2] : ""
            let service = cloudStorageProviders
                .first { leaf == $0.prefix || leaf.hasPrefix($0.prefix + "-") }?.service
            return .cloudSynced(service ?? "cloud storage")
        }

        for entry in cloudPrefixes where Array(relative.prefix(entry.components.count)) == entry.components {
            return .cloudSynced(entry.service)
        }
        return .ok
    }

    /// Bản dùng thật: đọc `volumeIsLocalKey` từ hệ thống tệp.
    public static func verdictOnDisk(for url: URL) -> LocationVerdict {
        verdict(for: url, home: FileManager.default.homeDirectoryForCurrentUser) { candidate in
            (try? candidate.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal
        }
    }
}
