import Foundation
import Translate

public enum ResetScope: Equatable {
    case history
    case savedWords
    case everything
}

/// Ba mức xoá. Mức 1 và 2 phải độc lập tuyệt đối — chúng có vòng đời khác
/// nhau và trộn chúng lại là mất dữ liệu người dùng không lấy lại được.
public struct DataReset {
    private let backend: TranslateBackend
    private let defaults: UserDefaults
    private let fileManager: FileManager

    public init(backend: TranslateBackend, defaults: UserDefaults = .standard,
                fileManager: FileManager = .default) {
        self.backend = backend
        self.defaults = defaults
        self.fileManager = fileManager
    }

    /// `dbPath`: db đang sống ở đâu NGAY BÂY GIỜ (có thể là chỗ người dùng đã
    /// tự chuyển tới qua "đổi vị trí lưu trữ"). `defaultDBPath`: chỗ app sẽ
    /// tự resolve về nếu không có override trong `UserDefaults` — chính là
    /// `DatabaseLocation.resolve` sẽ trả về ở lần khởi động kế tiếp một khi
    /// domain bị xoá sạch.
    ///
    /// Với `.history`/`.savedWords`, db không đổi chỗ nên vẫn sống ở `dbPath`
    /// sau khi gọi xong. Với `.everything` — thành công thì db sống ở
    /// `defaultDBPath` (đúng tham số caller truyền vào, không cần trả thêm gì
    /// để "biết" điều này); thất bại thì không còn store nào đang mở cả.
    @discardableResult
    public func perform(
        _ scope: ResetScope, dbPath: URL, defaultDBPath: URL,
        bundleID: String = DatabaseMigration.currentBundleID
    ) -> Bool {
        switch scope {
        case .history:
            return backend.clearHistory()
        case .savedWords:
            return backend.clearSavedWords()
        case .everything:
            _ = backend.closeStore()
            try? fileManager.removeItem(at: dbPath)
            for suffix in ["-wal", "-shm"] {
                try? fileManager.removeItem(at: URL(fileURLWithPath: dbPath.path + suffix))
            }
            defaults.removePersistentDomain(forName: bundleID)
            // Mở lại ở DEFAULT, không phải `dbPath`: xoá domain UserDefaults ở
            // trên đã xoá luôn `DatabaseLocation.overrideKey`, nên lần khởi
            // động SAU sẽ resolve về `defaultDBPath` bất kể `dbPath` từng là
            // gì. Mở lại ở `dbPath` cũ (một thư mục người dùng từng chuyển db
            // tới) sẽ để phiên này tiếp tục ghi vào đó trong khi lần khởi
            // động kế mất dấu nó vĩnh viễn — một file "mồ côi" không ai báo
            // cho người dùng biết (fix round 2, FIX 1).
            return backend.openStore(at: defaultDBPath)
        }
    }
}
