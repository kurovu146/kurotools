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

    @discardableResult
    public func perform(_ scope: ResetScope, dbPath: URL, bundleID: String) -> Bool {
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
            // Mở lại NGAY: `migrate()` dựng schema mới. Bỏ bước này thì app
            // chạy tiếp mà không có db cho tới lần khởi động sau.
            return backend.openStore(at: dbPath)
        }
    }
}
