import Foundation
import Translate

public enum ResetScope: Equatable {
    case history
    case savedWords
    case everything
}

/// Kết quả một lần xoá. Một `Bool` KHÔNG đủ cho `.everything`: hai kiểu thất
/// bại của nó đòi hai câu hoàn toàn khác nhau, và một cờ chung buộc caller
/// phải đoán — bản trước đoán "đã xoá xong nhưng không mở lại được", câu duy
/// nhất nó biết nói, kể cả khi chưa có gì bị xoá cả.
public enum ResetOutcome: Equatable {
    /// Xong, và có một store đang mở.
    case done
    /// Dừng TRƯỚC khi đụng vào bất cứ thứ gì — db, companion và preference
    /// còn nguyên như trước khi gọi.
    case failedNothingRemoved
    /// Đã xoá xong nhưng KHÔNG mở lại được store: app không còn db nào đang
    /// mở và không tự phục hồi được.
    case removedButStoreClosed
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
    ) -> ResetOutcome {
        switch scope {
        case .history:
            return backend.clearHistory() ? .done : .failedNothingRemoved
        case .savedWords:
            return backend.clearSavedWords() ? .done : .failedNothingRemoved
        case .everything:
            // Giao kèo `StoreMaintaining.closeStore()`: `false` nghĩa là "chưa
            // đóng được gì cả". Bỏ qua nó rồi xoá file là xoá đúng cái inode
            // mà Rust vẫn đang giữ — `kt_init` sau đó là no-op THÀNH CÔNG (đã
            // có store mở), nên `openStore` trả `true`, model báo "Đã xoá
            // sạch", và mọi lần tra tiếp theo ghi vào một file đã unlink cho
            // tới lúc thoát app. `DataRelocation` gác đúng lời gọi này bằng
            // một guard sáu dòng chú thích; chỗ này phải gác y hệt.
            guard backend.closeStore() else { return .failedNothingRemoved }
            remove(databaseAt: dbPath)
            defaults.removePersistentDomain(forName: bundleID)
            // Mở lại ở DEFAULT, không phải `dbPath`: xoá domain UserDefaults ở
            // trên đã xoá luôn `DatabaseLocation.overrideKey`, nên lần khởi
            // động SAU sẽ resolve về `defaultDBPath` bất kể `dbPath` từng là
            // gì. Mở lại ở `dbPath` cũ (một thư mục người dùng từng chuyển db
            // tới) sẽ để phiên này tiếp tục ghi vào đó trong khi lần khởi
            // động kế mất dấu nó vĩnh viễn — một file "mồ côi" không ai báo
            // cho người dùng biết (fix round 2, FIX 1).
            return backend.openStore(at: defaultDBPath) ? .done : .removedButStoreClosed
        }
    }

    /// Xoá db chính CÙNG companion của nó. Journal mode là `delete` nên
    /// `-wal`/`-shm` thường không tồn tại — `removeItem` với file không có là
    /// no-op, và bỏ chúng lại cạnh một db vừa bị xoá là để SQLite mở db mới
    /// lên trên một cặp companion mồ côi.
    private func remove(databaseAt path: URL) {
        try? fileManager.removeItem(at: path)
        for suffix in DatabaseMigration.companionSuffixes {
            try? fileManager.removeItem(at: URL(fileURLWithPath: path.path + suffix))
        }
    }
}
