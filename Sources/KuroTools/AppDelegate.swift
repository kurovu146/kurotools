import AppKit
import Translate
import Vitals

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let vitals = VitalsController()
    private let translate = TranslateController()
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ note: Notification) {
        vitals.start()
        vitals.attach(menu: menu)

        let lookupItem = NSMenuItem(title: "Tra từ đang chọn  ⌘⇧D",
                                    action: #selector(triggerLookup), keyEquivalent: "")
        lookupItem.target = self
        vitals.extraItems = [lookupItem]

        translate.start(dbPath: DatabaseMigration.resolveDatabase(
            appSupport: DatabaseMigration.defaultAppSupport()))
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
