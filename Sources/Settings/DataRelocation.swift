import Foundation
import Translate

/// Những thao tác vòng đời store mà việc đổi chỗ db cần. Tách riêng khỏi
/// `TranslateBackend` để chỗ này không phải biết gì về tra cứu, và để test
/// dựng được một store giả rẻ tiền.
public protocol StoreMaintaining: AnyObject {
    /// Đóng store đang mở. Giao kèo: `false` PHẢI nghĩa là "chưa đóng được
    /// gì cả, mọi thứ còn nguyên như trước" — không phải "đóng dở". Pre-flight
    /// guard trong `relocate` dựa thẳng vào điều này để return luôn mà KHÔNG
    /// thử mở lại khi thấy `false`. Một implementation lỡ đóng rồi mới báo
    /// lỗi sẽ khiến `relocate` nghĩ store vẫn đang mở trong khi thực ra không
    /// — rơi đúng vào cái hố `.failedAndStoreClosed` được sinh ra để bắt.
    func closeStore() -> Bool
    func openStore(at dbPath: URL) -> Bool
    /// Đọc thật một lần. `Connection::open` tạo file rỗng cho đường dẫn sai mà
    /// VẪN báo thành công — mở được không chứng minh được gì.
    func canRead() -> Bool
}

public enum RelocationOutcome: Equatable {
    case moved(to: URL, oldRenamedTo: URL)
    case rejected(LocationVerdict)
    /// Không chuyển được, và dữ liệu vẫn nguyên vẹn.
    ///
    /// `storeIsOpen` phân biệt hai loại thất bại mà caller KHÔNG suy ra được
    /// từ chuỗi lý do: `true` = rollback đã mở lại được db cũ (store đang mở);
    /// `false` = guard pre-flight từ chối TRƯỚC khi `closeStore()` được gọi,
    /// nên lời gọi này không chứng minh gì về trạng thái store. Năm trong sáu
    /// đường trả `.failed` là loại thứ hai — một caller coi mọi `.failed` là
    /// "store đang mở" sẽ gỡ cảnh báo khởi động lại sau một lần thử lại bị
    /// từ chối, trong khi app vẫn không có db nào mở.
    case failed(String, storeIsOpen: Bool)
    /// Rollback KHÔNG mở lại được store cũ — không còn store nào đang mở ở
    /// đâu cả. Nghiêm trọng hơn `.failed`, phải được hiển thị khác đi.
    case failedAndStoreClosed(String)
}

/// Đổi chỗ db theo lối copy-verify-swap. Không bao giờ `move`.
///
/// Bất biến: khi hàm này trả về, TRỪ nhánh `.failedAndStoreClosed`, luôn có
/// một store mở được tại đường dẫn đang có hiệu lực. Gặp
/// `.failedAndStoreClosed` nghĩa là rollback không mở lại được store cũ —
/// không còn store nào đang mở ở đâu cả; caller PHẢI báo người dùng khởi
/// động lại app, vì không có cách nào tự phục hồi từ đây (không biết được
/// trạng thái thật của driver Rust nữa).
public enum DataRelocation {
    // Tên file trùng với `DatabaseMigration` không phải trùng hợp — cùng một
    // db. Tham chiếu thẳng, đừng khai báo lại một hằng số thứ hai có thể trôi
    // khỏi bản gốc.
    private static var databaseName: String { DatabaseMigration.databaseName }
    private static var companionSuffixes: [String] { DatabaseMigration.companionSuffixes }

    public static func relocate(
        currentDB: URL,
        toDirectory: URL,
        store: StoreMaintaining,
        fileManager: FileManager = .default,
        verdict: (URL) -> LocationVerdict = LocalVolumeCheck.verdictOnDisk,
        now: Date = Date(),
        willCloseStore: () -> Void = {}
    ) -> RelocationOutcome {
        let target = toDirectory.appendingPathComponent(databaseName)

        // ── Kiểm tra trước, TRƯỚC khi đóng store ────────────────────────────
        // Mọi lý do từ chối phải được biết khi app vẫn đang chạy bình thường.
        //
        // So bằng CHUỖI đường dẫn đã standardize, không bằng `URL ==`: `URL ==`
        // nhạy với dấu `/` cuối, và `resolvingSymlinksInPath()` không tự
        // chuẩn hoá nó — `deletingLastPathComponent()` (có `/`) không bao giờ
        // bằng `appendingPathComponent()` (không `/`) dù cùng trỏ một thư mục.
        let currentDirPath = currentDB.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        let targetDirPath = toDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        guard currentDirPath != targetDirPath else {
            return .failed("Thư mục đích trùng chỗ hiện tại.", storeIsOpen: false)
        }
        let check = verdict(toDirectory)
        guard check == .ok else { return .rejected(check) }
        guard !fileManager.fileExists(atPath: target.path) else {
            return .failed("Đã có ktranslate.db trong thư mục đích.", storeIsOpen: false)
        }
        guard fileManager.isWritableFile(atPath: toDirectory.path) else {
            return .failed("Không ghi được vào thư mục đích.", storeIsOpen: false)
        }
        guard fileManager.fileExists(atPath: currentDB.path) else {
            return .failed("Không tìm thấy db ở chỗ hiện tại.", storeIsOpen: false)
        }

        // ── Đóng, copy, mở lại, đọc thử ─────────────────────────────────────
        // `closeStore()` được kiểm: Rust `kt_init` là no-op thành công khi đã
        // có store mở (đóng được thì `STORE` mới là `None`) — nếu đóng thất
        // bại mà ta vẫn cứ copy, `openStore(target)` sẽ "thành công" trong khi
        // thực ra vẫn đang ghi vào db CŨ, và `canRead()` đọc trúng chính db cũ
        // nên cũng "qua" — `.moved` báo giả trong khi mọi write sau đó rơi vào
        // file sắp bị đổi tên. Chưa copy gì nên không cần dọn.
        // Spec §5 bước 2: đóng popup tra từ rồi mới `kt_close()`. Móc ở ĐÂY
        // chứ không phải ở caller vì mọi lý do từ chối (bước 1) nằm phía trên —
        // đóng popup của người dùng cho một lần chọn thư mục bị từ chối là làm
        // phiền không đổi lại được gì.
        willCloseStore()
        guard store.closeStore() else {
            // `closeStore()` trả `false` nghĩa là "chưa đóng được gì cả" theo giao
            // kèo — nhưng nó không nói store CÓ đang mở hay không (nó có thể đã
            // đóng từ một lần hỏng trước). Không chứng minh được thì báo false.
            return .failed("Không đóng được store hiện tại.", storeIsOpen: false)
        }

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
        // Companion đi theo `.db` chính — để chúng lại dưới tên cũ, không
        // stamp, thì bản backup (bản sao DUY NHẤT của trạng thái cũ) tách rời
        // khỏi companion mà SQLite cần, và nằm đúng chỗ một db mặc định mới
        // sẽ được tạo ra tiếp theo. Best-effort như lúc copy.
        for suffix in companionSuffixes {
            let from = URL(fileURLWithPath: currentDB.path + suffix)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try? fileManager.moveItem(at: from, to: URL(fileURLWithPath: renamed.path + suffix))
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
        guard store.openStore(at: currentDB) else {
            return .failedAndStoreClosed(
                "\(reason) Mở lại db cũ cũng thất bại — hiện không có store nào đang mở.")
        }
        // Đây là đường DUY NHẤT trả `.failed` với store chắc chắn đang mở:
        // `openStore(currentDB)` vừa thành công ngay phía trên.
        return .failed(reason, storeIsOpen: true)
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
