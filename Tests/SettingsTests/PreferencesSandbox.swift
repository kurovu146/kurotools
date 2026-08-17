import Foundation

/// Suite `UserDefaults` dùng một lần cho test, dọn được HẲN.
///
/// `removePersistentDomain(forName:)` chỉ làm RỖNG nội dung — file
/// `~/Library/Preferences/<suite>.plist` vẫn nằm lại trên máy thật, mỗi lần
/// chạy bộ test lại thêm một cái (đo được: một lần chạy `SettingsModelTests`
/// để lại 10 file mới). Test không được phép để lại rác trên máy người dùng,
/// nên `destroy` xoá luôn file.
enum PreferencesSandbox {
    /// Tiền tố bắt buộc — `destroy` chỉ xoá file mang đúng tiền tố này, để
    /// một tên truyền nhầm không bao giờ chạm tới preference thật của app
    /// (`com.kurovu.kurotools`) hay của bất kỳ app nào khác.
    static let prefix = "kurotools.test."

    static func make(_ label: String) -> (defaults: UserDefaults, suiteName: String) {
        let name = "\(prefix)\(label).\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    static func destroy(_ suiteName: String) {
        guard suiteName.hasPrefix(prefix) else { return }
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeSuite(named: suiteName)
        // `CFPreferences` ghi lười: đồng bộ trước khi xoá file, nếu không một
        // lần flush muộn có thể dựng lại đúng file vừa xoá.
        CFPreferencesAppSynchronize(suiteName as CFString)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }
}
