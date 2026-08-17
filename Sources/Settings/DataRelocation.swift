import Foundation

/// Những thao tác vòng đời store mà việc đổi chỗ db cần. Tách riêng khỏi
/// `TranslateBackend` để chỗ này không phải biết gì về tra cứu, và để test
/// dựng được một store giả rẻ tiền.
public protocol StoreMaintaining: AnyObject {
    func closeStore() -> Bool
    func openStore(at dbPath: URL) -> Bool
    /// Đọc thật một lần. `Connection::open` tạo file rỗng cho đường dẫn sai mà
    /// VẪN báo thành công — mở được không chứng minh được gì.
    func canRead() -> Bool
}

public enum RelocationOutcome: Equatable {
    case moved(to: URL, oldRenamedTo: URL)
    case rejected(LocationVerdict)
    case failed(String)
}

/// Đổi chỗ db theo lối copy-verify-swap. Không bao giờ `move`.
///
/// Bất biến: khi hàm này trả về — dù nhánh nào — luôn có một store mở được
/// tại đường dẫn đang có hiệu lực.
public enum DataRelocation {
    static let databaseName = "ktranslate.db"
    static let companionSuffixes = ["-wal", "-shm"]

    public static func relocate(
        currentDB: URL,
        toDirectory: URL,
        store: StoreMaintaining,
        fileManager: FileManager = .default,
        verdict: (URL) -> LocationVerdict = LocalVolumeCheck.verdictOnDisk,
        now: Date = Date()
    ) -> RelocationOutcome {
        let target = toDirectory.appendingPathComponent(databaseName)

        // ── Kiểm tra trước, TRƯỚC khi đóng store ────────────────────────────
        // Mọi lý do từ chối phải được biết khi app vẫn đang chạy bình thường.
        let currentDir = currentDB.deletingLastPathComponent().resolvingSymlinksInPath()
        guard currentDir != toDirectory.resolvingSymlinksInPath() else {
            return .failed("Thư mục đích trùng chỗ hiện tại.")
        }
        let check = verdict(toDirectory)
        guard check == .ok else { return .rejected(check) }
        guard !fileManager.fileExists(atPath: target.path) else {
            return .failed("Đã có ktranslate.db trong thư mục đích.")
        }
        guard fileManager.isWritableFile(atPath: toDirectory.path) else {
            return .failed("Không ghi được vào thư mục đích.")
        }

        // ── Đóng, copy, mở lại, đọc thử ─────────────────────────────────────
        _ = store.closeStore()

        do {
            try fileManager.copyItem(at: currentDB, to: target)
        } catch {
            try? fileManager.removeItem(at: target)
            return rollback(to: currentDB, store: store, reason: "Copy thất bại: \(error.localizedDescription)")
        }
        for suffix in companionSuffixes {
            let from = URL(fileURLWithPath: currentDB.path + suffix)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try? fileManager.copyItem(at: from, to: URL(fileURLWithPath: target.path + suffix))
        }

        guard store.openStore(at: target) else {
            cleanUp(target, fileManager: fileManager)
            return rollback(to: currentDB, store: store, reason: "Không mở được db ở chỗ mới.")
        }
        guard store.canRead() else {
            cleanUp(target, fileManager: fileManager)
            return rollback(to: currentDB, store: store, reason: "Db ở chỗ mới mở được nhưng không đọc được.")
        }

        // ── Thành công: đổi tên bản cũ, KHÔNG xoá ───────────────────────────
        let stamp = ISO8601DateFormatter.stampFormatter.string(from: now)
        let renamed = URL(fileURLWithPath: currentDB.path + ".moved-\(stamp)")
        do {
            try fileManager.moveItem(at: currentDB, to: renamed)
        } catch {
            // Db mới đã chạy được; không đổi tên được bản cũ là chuyện phiền,
            // không phải hỏng. Báo đường dẫn cũ để người dùng tự dọn.
            NSLog("KuroTools: could not rename the old database: \(error)")
            return .moved(to: target, oldRenamedTo: currentDB)
        }
        return .moved(to: target, oldRenamedTo: renamed)
    }

    private static func cleanUp(_ target: URL, fileManager: FileManager) {
        try? fileManager.removeItem(at: target)
        for suffix in companionSuffixes {
            try? fileManager.removeItem(at: URL(fileURLWithPath: target.path + suffix))
        }
    }

    private static func rollback(
        to currentDB: URL, store: StoreMaintaining, reason: String
    ) -> RelocationOutcome {
        _ = store.closeStore()
        _ = store.openStore(at: currentDB)
        return .failed(reason)
    }
}

extension ISO8601DateFormatter {
    /// `2026-08-17T101500Z` — an toàn cho tên file, vẫn đọc được bằng mắt.
    static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate,
                           .withTime, .withTimeZone]
        return f
    }()
}
