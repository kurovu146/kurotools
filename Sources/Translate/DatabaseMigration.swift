import Foundation

/// Đổi bundle id nghĩa là `Application Support` trỏ sang thư mục khác. Lần đổi
/// tên trước (`tra` → `ktranslate`) phải `sqlite3 .backup` bằng tay và bất kỳ
/// bản cài nào khác sẽ khởi động rỗng. Lần này app tự lo.
public enum DatabaseMigration {
    static let currentBundleID = "com.kurovu.kurotools"
    static let legacyBundleIDs = ["com.kurovu.ktranslate", "com.kurovu.tra"]
    static let databaseName = "ktranslate.db"
    /// SQLite giữ trạng thái ở ba file. Copy mỗi `.db` là mời một db hỏng.
    static let companionSuffixes = ["", "-wal", "-shm"]

    public static func resolveDatabase(appSupport: URL, fileManager: FileManager = .default) -> URL {
        let newDir = appSupport.appendingPathComponent(currentBundleID)
        let newDB = newDir.appendingPathComponent(databaseName)
        try? fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)

        // Đã có db thì không bao giờ đụng vào — migration chạy đúng một lần, và
        // "một lần" phải đúng cả khi thư mục cũ còn nằm đó mãi mãi.
        guard !fileManager.fileExists(atPath: newDB.path) else { return newDB }

        for legacy in legacyBundleIDs {
            let legacyDir = appSupport.appendingPathComponent(legacy)
            guard fileManager.fileExists(atPath: legacyDir.appendingPathComponent(databaseName).path)
            else { continue }
            for suffix in companionSuffixes {
                let from = legacyDir.appendingPathComponent(databaseName + suffix)
                let to = newDir.appendingPathComponent(databaseName + suffix)
                guard fileManager.fileExists(atPath: from.path) else { continue }
                try? fileManager.copyItem(at: from, to: to)
            }
            NSLog("KuroTools: migrated database from \(legacy)")
            break
        }
        return newDB
    }

    public static func defaultAppSupport(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}
