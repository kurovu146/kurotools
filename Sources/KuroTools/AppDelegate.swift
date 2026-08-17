import AppKit
import Settings
import Translate
import Vitals

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let vitals = VitalsController()
    private let translate = TranslateController()
    private let menu = NSMenu()
    /// Dựng SAU `translate.start(dbPath:)` — `SettingsModel` cần `dbPath`
    /// thật, không phải chỗ nó SẼ nằm. IUO vì mọi lối dùng khác đều chạy sau
    /// `applicationDidFinishLaunching`, giống `reader` trong `VitalsController`.
    private var settingsModel: SettingsModel!

    func applicationDidFinishLaunching(_ note: Notification) {
        // `vitals.start()` gọi `NSApp.terminate(nil)` khi không mở được SMC —
        // lệnh đó BẤT ĐỒNG BỘ (chỉ lên lịch thoát), nên thiếu guard này thì
        // phần dưới vẫn chạy tiếp trên một máy sắp thoát (minor, final
        // review): đăng ký hotkey toàn cục, chạy migration, mở SQLite.
        guard vitals.start() else { return }
        vitals.attach(menu: menu)

        let lookupItem = NSMenuItem(title: "Tra từ đang chọn  ⌘⇧D",
                                    action: #selector(triggerLookup), keyEquivalent: "")
        lookupItem.target = self
        vitals.extraItems = [lookupItem]

        let dbPath = DatabaseLocation.resolve(appSupport: DatabaseMigration.defaultAppSupport())
        translate.start(dbPath: dbPath)

        settingsModel = SettingsModel(
            translate: translate,
            vitals: vitals,
            backend: translate.backend,
            loginItem: SMAppServiceLoginItem(),
            dbPath: dbPath)

        // Vitals không được biết module Settings tồn tại (phụ thuộc phải một
        // chiều) — AppDelegate là nơi duy nhất import cả hai nên chỗ nối phải
        // nằm ở đây.
        vitals.onOpenSettings = { [weak self] in
            guard let self else { return }
            SettingsWindowController.show(model: self.settingsModel)
        }
    }

    // Không trong brief gốc: giữ hành vi cũ của AppDelegate KuroVitals — revert
    // fan về auto ở MỌI đường terminate, không chỉ nút Quit trong menu (vd.
    // shutdown/logout hệ thống cũng gửi applicationWillTerminate cho accessory
    // app). Bỏ dòng này sẽ làm mất luôn safety net cũ.
    func applicationWillTerminate(_ note: Notification) {
        vitals.stop()
    }

    @objc private func triggerLookup() { translate.toggle() }
}
