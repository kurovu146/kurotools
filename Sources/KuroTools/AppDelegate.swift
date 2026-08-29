import AppKit
import Settings
import Translate
import Vitals
import Wallpaper

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let vitals = VitalsController()
    private let translate = TranslateController()
    private let wallpaper = VideoWallpaperController()
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

        // Dựng LẠI mỗi lần dropdown mở, từ tổ hợp đang thật sự sống. Bản trước
        // gán một `NSMenuItem` duy nhất với nhãn `⌘⇧D` gõ tay: đổi phím tắt
        // trong Settings thì cửa sổ hiện tổ hợp mới còn menu vẫn quảng cáo tổ
        // hợp cũ — và ngay ở mặc định hai chỗ đã mâu thuẫn, vì
        // `HotkeyCombo.displayString` xếp theo thứ tự macOS (`⇧⌘D`).
        vitals.extraItemsProvider = { [weak self] in
            guard let self else { return [] }
            let lookupItem = NSMenuItem(title: LookupMenuItem.title(for: translate.currentHotkey),
                                        action: #selector(triggerLookup), keyEquivalent: "")
            lookupItem.target = self

            // Hình nền video: toggle nhanh trong menu. Chưa chọn video thì
            // mục này bị khoá — bật từ menu khi chưa có video là chẳng có gì
            // để hiện, và chỉ đường về Settings còn rõ hơn một công tắc vô
            // hiệu hoá bí hiểm.
            let wallpaperItem = NSMenuItem(title: "Hình nền video",
                                           action: #selector(toggleVideoWallpaper), keyEquivalent: "")
            wallpaperItem.target = self
            if wallpaper.videoURL == nil {
                wallpaperItem.title = "Hình nền video — chưa chọn video"
                wallpaperItem.isEnabled = false
            } else {
                wallpaperItem.state = wallpaper.isEnabled ? .on : .off
            }
            return [lookupItem, wallpaperItem]
        }

        // Khôi phục cửa sổ wallpaper từ lần chạy trước (bật sẵn nếu đã chọn
        // video + enabled). Chạy TRƯỚC khi dựng SettingsModel — model đọc
        // trạng thái từ controller, không phải từ đĩa.
        wallpaper.restore()

        let dbPath = DatabaseLocation.resolve(appSupport: DatabaseMigration.defaultAppSupport())
        translate.start(dbPath: dbPath)

        settingsModel = SettingsModel(
            translate: translate,
            vitals: vitals,
            backend: translate.backend,
            loginItem: SMAppServiceLoginItem(),
            wallpaper: wallpaper,
            // Installer THẬT chỉ được dựng ở đây, chỗ duy nhất được phép chạm
            // container của screensaver — `SettingsModel` không tự dựng nổi
            // một cái, nên không test nào lỡ tay lấy trúng.
            saverInstaller: SaverVideoInstaller(),
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

    @objc private func toggleVideoWallpaper() {
        wallpaper.setEnabled(!wallpaper.isEnabled)
    }
}
