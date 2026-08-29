import AppKit
import Settings
import Translate
import Vitals
import Wallpaper

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let vitals = VitalsController()
    private let translate = TranslateController()
    /// Tiêm được để test dựng được ca "chưa chọn video" mà không phụ thuộc
    /// video người dùng đang thật sự lưu — `VideoWallpaperController` đọc
    /// trạng thái từ `store` ngay trong `init`, và không dựng cửa sổ nào cho
    /// tới lần `restore()`/`setEnabled` đầu tiên.
    private let wallpaper: VideoWallpaperController
    private let menu = NSMenu()
    /// Dựng SAU `translate.start(dbPath:)` — `SettingsModel` cần `dbPath`
    /// thật, không phải chỗ nó SẼ nằm. IUO vì mọi lối dùng khác đều chạy sau
    /// `applicationDidFinishLaunching`, giống `reader` trong `VitalsController`.
    private var settingsModel: SettingsModel!

    /// `VideoWallpaperController()` dựng trong THÂN init chứ không làm default
    /// argument: biểu thức mặc định chạy ở ngữ cảnh nonisolated, mà `init` của
    /// nó là `@MainActor` — cùng ca đã ghi trong `SettingsModel.init`.
    init(wallpaper: VideoWallpaperController? = nil) {
        self.wallpaper = wallpaper ?? VideoWallpaperController()
        super.init()
    }

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
            self?.makeExtraMenuItems() ?? []
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

    /// Tách khỏi `applicationDidFinishLaunching` để test dựng được đúng những
    /// mục này: cái kia đứng sau `vitals.start()`, tức là sau một lần mở SMC
    /// thật.
    func makeExtraMenuItems() -> [NSMenuItem] {
        let lookupItem = NSMenuItem(title: LookupMenuItem.title(for: translate.currentHotkey),
                                    action: #selector(triggerLookup), keyEquivalent: "")
        lookupItem.target = self

        // Hình nền video: toggle nhanh trong menu. Chưa chọn video thì mục này
        // bị khoá — bật từ menu khi chưa có video là chẳng có gì để hiện, và
        // chỉ đường về Settings còn rõ hơn một công tắc vô hiệu hoá bí hiểm.
        // Việc khoá nằm ở `validateMenuItem` chứ KHÔNG phải một `isEnabled`
        // gán ở đây: xem chú thích ở đó.
        let wallpaperItem = NSMenuItem(title: "Hình nền video",
                                       action: #selector(toggleVideoWallpaper), keyEquivalent: "")
        wallpaperItem.target = self
        if wallpaper.videoURL == nil {
            wallpaperItem.title = "Hình nền video — chưa chọn video"
        } else {
            wallpaperItem.state = wallpaper.isEnabled ? .on : .off
        }
        return [lookupItem, wallpaperItem]
    }

    @objc private func triggerLookup() { translate.toggle() }

    @objc private func toggleVideoWallpaper() {
        wallpaper.setEnabled(!wallpaper.isEnabled)
    }
}

extension AppDelegate: NSMenuItemValidation {
    /// Gán `isEnabled = false` lúc dựng mục KHÔNG khoá được nó: `menu` là một
    /// `NSMenu` với `autoenablesItems` mặc định `true`, nên trước khi dropdown
    /// hiện, AppKit chạy một lượt tự bật lại mọi mục có target respond được
    /// selector — và ghi đè đúng cái cờ vừa đặt. (`MenuBarController` khoá
    /// được các mục của nó vì chúng có `action: nil`, một đường khác hẳn.)
    ///
    /// Hệ quả của việc mục đó vẫn bấm được: `setEnabled(true)` PERSIST một
    /// preference ẩn rồi `rebuild()` bail vì chưa có video — không có gì xảy
    /// ra, không lời giải thích, và lần chọn video sau đó wallpaper tự bật.
    ///
    /// `autoenablesItems = false` sửa được ca này nhưng phá ca kia: `menu` dùng
    /// chung với `VitalsController`, và các mục `action: nil` của nó sẽ hết bị
    /// xám. Validation chỉ chạm đúng mục có target là `self`.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(toggleVideoWallpaper) else { return true }
        return wallpaper.videoURL != nil
    }
}
