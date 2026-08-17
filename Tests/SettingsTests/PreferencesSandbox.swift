import Foundation

/// Suite `UserDefaults` dùng cho test, KHÔNG sinh thêm file mới mỗi lần chạy.
///
/// Cách cũ (`kurotools.settings.<UUID>` mỗi test) để lại một file plist trong
/// `~/Library/Preferences` của máy thật cho MỖI test, mãi mãi —
/// `removePersistentDomain` chỉ làm rỗng nội dung chứ không xoá file.
///
/// Xoá thẳng file trong `tearDown` KHÔNG cứu được, đã đo bằng probe riêng:
/// xoá xong file biến mất thật, nhưng đối tượng `UserDefaults` của suite vẫn
/// còn sống trong tiến trình test, và tới lúc tiến trình THOÁT nó flush lại
/// domain đang giữ trong bộ nhớ — cfprefsd dựng lại đúng file vừa xoá
/// (probe: `exists` = false ngay sau khi xoá, rồi = true sau khi process kết
/// thúc).
///
/// Nên cách duy nhất giữ máy sạch là KHÔNG sinh tên mới: mỗi lớp test dùng một
/// tên CỐ ĐỊNH, dọn rỗng trước và sau mỗi test. Máy giữ đúng một file cho mỗi
/// lớp, dùng lại mãi, thay vì một file cho mỗi test cho mỗi lần chạy.
///
/// An toàn vì `swift test` chạy các lớp test tuần tự (không bật `--parallel`);
/// hai lớp dùng hai `label` khác nhau nên không bao giờ đụng nhau.
enum PreferencesSandbox {
    /// Tiền tố bắt buộc — mọi thao tác xoá đều kiểm nó, để một tên truyền
    /// nhầm không bao giờ chạm tới preference thật của app
    /// (`com.kurovu.kurotools`) hay của bất kỳ app nào khác.
    static let prefix = "kurotools.test."

    /// Dọn RỖNG trước khi trả về: phần sót của lần chạy trước (hoặc của một
    /// test trước trong cùng lớp) không được chảy sang test này.
    static func make(_ label: String) -> (defaults: UserDefaults, suiteName: String) {
        let name = "\(prefix)\(label)"
        let defaults = UserDefaults(suiteName: name)!
        wipe(name)
        return (defaults, name)
    }

    static func destroy(_ suiteName: String) {
        wipe(suiteName)
    }

    private static func wipe(_ suiteName: String) {
        guard suiteName.hasPrefix(prefix) else { return }
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
