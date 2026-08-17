import Foundation

/// Đổi bundle id nghĩa là `Application Support` trỏ sang thư mục khác. Lần đổi
/// tên trước (`tra` → `ktranslate`) phải `sqlite3 .backup` bằng tay và bất kỳ
/// bản cài nào khác sẽ khởi động rỗng. Lần này app tự lo.
public enum DatabaseMigration {
    static let currentBundleID = "com.kurovu.kurotools"
    static let legacyBundleIDs = ["com.kurovu.ktranslate", "com.kurovu.tra"]
    public static let databaseName = "ktranslate.db"
    /// SQLite giữ trạng thái ở ba file — `.db` chính được copy riêng ở dưới
    /// (kiểm lỗi, không nuốt); hai file này là companion, best-effort.
    public static let companionSuffixes = ["-wal", "-shm"]

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

            // File `.db` CHÍNH: kiểm kết quả, đừng nuốt (M-2, final review).
            // `try?` cũ coi một lần copy hỏng-giữa-chừng (đĩa đầy...) y hệt
            // một lần thành công — log "migrated" là một lời NÓI DỐI, và tệ
            // hơn, file dở dang copyItem để lại ở `newDB` khiến guard
            // `fileExists` phía trên coi migration đã XONG mãi mãi ở lần gọi
            // kế tiếp, không bao giờ thử lại. Dọn phần dở dang trước khi trả
            // về để lần gọi sau còn thấy `newDB` chưa tồn tại.
            let mainFrom = legacyDir.appendingPathComponent(databaseName)
            let mainTo = newDir.appendingPathComponent(databaseName)
            do {
                try fileManager.copyItem(at: mainFrom, to: mainTo)
            } catch {
                try? fileManager.removeItem(at: mainTo)
                NSLog("KuroTools: failed to migrate database from \(legacy): \(error)")
                return newDB
            }

            // `-wal`/`-shm` là companion, best-effort: thiếu chúng làm mất vài
            // giao dịch gần nhất, không làm hỏng file `.db` chính vừa copy
            // thành công ở trên.
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

/// Vị trí db: mặc định trong `Application Support` của bundle hiện tại, hoặc
/// một thư mục người dùng chọn trong Settings.
public enum DatabaseLocation {
    public static let overrideKey = "databaseDirectory"

    /// Đường dẫn file db sẽ dùng cho lần khởi động này.
    ///
    /// Override trỏ vào chỗ không còn tồn tại → quay về mặc định và ghi log.
    /// Ổ ngoài rút ra là chuyện bình thường; một preference cũ không được
    /// phép làm app không khởi động được.
    public static func resolve(
        appSupport: URL, defaults: UserDefaults = .standard, fileManager: FileManager = .default
    ) -> URL {
        if let path = defaults.string(forKey: overrideKey) {
            let db = URL(fileURLWithPath: path)
                .appendingPathComponent(DatabaseMigration.databaseName)
            if fileManager.fileExists(atPath: db.path) { return db }
            NSLog("KuroTools: database override \(path) is gone; falling back to the default")
        }
        return DatabaseMigration.resolveDatabase(appSupport: appSupport, fileManager: fileManager)
    }

    public static func setOverride(_ directory: URL?, defaults: UserDefaults = .standard) {
        guard let directory else {
            defaults.removeObject(forKey: overrideKey)
            return
        }
        defaults.set(directory.path, forKey: overrideKey)
    }
}
