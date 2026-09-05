import XCTest
import SensorReader
@testable import Vitals

/// Target giả cho `populate(...)` — chỉ cần tồn tại đúng selector, không cần
/// làm gì khi bấm; test chỉ quan tâm cấu trúc menu được dựng ra.
@MainActor
private final class DummyTarget: NSObject {
    @objc func applyFanPreset(_ sender: NSMenuItem) {}
    @objc func autoFan(_ sender: NSMenuItem) {}
    @objc func allAuto() {}
    @objc func presetQuiet() {}
    @objc func presetMax() {}
    @objc func openSettings() {}
    @objc func showProcesses() {}
    @objc func quit() {}
}

@MainActor
final class MenuBarControllerTests: XCTestCase {
    /// Task 13: submenu Settings cũ (Show Temp/CPU/RAM + ngưỡng °C) biến mất,
    /// thay bằng một mục "Settings…" mở cửa sổ Settings. Assert cả target lẫn
    /// action/keyEquivalent — chỉ so title thì không chứng minh được gì về
    /// việc nó có thật sự được nối dây hay không.
    func testPopulateRepresentsASingleSettingsItemWiredToOpenSettings() {
        let controller = MenuBarController()
        let menu = NSMenu()
        let target = DummyTarget()
        let snapshot = Snapshot(cpuTempC: 40, cpuLoadPct: 10, ramUsedGB: 4, ramTotalGB: 16, fans: [])

        controller.populate(
            menu: menu, snapshot: snapshot, settings: Settings(), target: target,
            applyFanPreset: #selector(DummyTarget.applyFanPreset(_:)),
            autoFan: #selector(DummyTarget.autoFan(_:)),
            allAuto: #selector(DummyTarget.allAuto),
            presetQuiet: #selector(DummyTarget.presetQuiet),
            presetMax: #selector(DummyTarget.presetMax),
            openSettings: #selector(DummyTarget.openSettings),
            showProcesses: #selector(DummyTarget.showProcesses),
            quit: #selector(DummyTarget.quit))

        guard let settingsItem = menu.items.first(where: { $0.title == "Settings…" }) else {
            return XCTFail("expected a \"Settings…\" item in the populated menu")
        }
        XCTAssertEqual(settingsItem.keyEquivalent, ",")
        XCTAssertEqual(settingsItem.action, #selector(DummyTarget.openSettings))
        XCTAssertTrue(settingsItem.target === target,
            "item must be wired to the given target, not just carry the right title")

        // Cũ: submenu "Settings" (Show Temp/CPU/RAM + ngưỡng °C) đã chuyển
        // hẳn vào cửa sổ Settings (Task 12) — không còn trong dropdown.
        XCTAssertNil(menu.items.first(where: { $0.title == "Settings" }),
            "the old \"Settings\" submenu parent must no longer exist")
        for staleTitle in ["Show Temp", "Show CPU", "Show RAM", "Alert Threshold", "90°C", "95°C", "100°C"] {
            XCTAssertNil(menu.items.first(where: { $0.title == staleTitle }),
                "\"\(staleTitle)\" belonged to the removed submenu and must not appear top-level either")
        }
    }

    private func populate(_ menu: NSMenu, fans: [FanReading], target: DummyTarget) {
        MenuBarController().populate(
            menu: menu,
            snapshot: Snapshot(cpuTempC: 40, cpuLoadPct: 10, ramUsedGB: 4, ramTotalGB: 16, fans: fans),
            settings: Settings(), target: target,
            applyFanPreset: #selector(DummyTarget.applyFanPreset(_:)),
            autoFan: #selector(DummyTarget.autoFan(_:)),
            allAuto: #selector(DummyTarget.allAuto),
            presetQuiet: #selector(DummyTarget.presetQuiet),
            presetMax: #selector(DummyTarget.presetMax),
            openSettings: #selector(DummyTarget.openSettings),
            showProcesses: #selector(DummyTarget.showProcesses),
            quit: #selector(DummyTarget.quit))
    }

    /// Máy không có quạt điều khiển được (MacBook Air, hoặc máy mà SMC không
    /// trả lời key quạt). Bản trước vẫn dựng "Tất cả Auto / Quiet / Max" —
    /// ba nút ghi SMC lên phần cứng không có thật, người dùng bấm mà không có
    /// gì xảy ra và không biết vì sao.
    func testMenuDropsEveryFanControlWhenNoFanIsControllable() {
        let menu = NSMenu()
        populate(menu, fans: [], target: DummyTarget())
        let titles = menu.items.map(\.title)

        for gone in ["Tất cả Auto", "Quiet (min) tất cả", "Max tất cả"] {
            XCTAssertNil(menu.items.first { $0.title == gone },
                "\"\(gone)\" ghi SMC nên không được xuất hiện khi không có quạt; menu: \(titles)")
        }
        XCTAssertNil(menu.items.first { $0.title.hasPrefix("Quạt ") },
                     "không được dựng submenu quạt; menu: \(titles)")

        // Phải NÓI vì sao, không im lặng bỏ mục đi.
        guard let reason = menu.items.first(where: { $0.title.contains("không có quạt") }) else {
            return XCTFail("thiếu dòng giải thích vì sao mất điều khiển quạt; menu: \(titles)")
        }
        XCTAssertFalse(reason.isEnabled, "dòng giải thích là thông tin, không bấm được")

        // Phần không liên quan tới quạt vẫn phải còn nguyên.
        XCTAssertNotNil(menu.items.first { $0.title == "Settings…" })
        XCTAssertNotNil(menu.items.first { $0.title == "Tiến trình..." })
    }

    /// Mặt còn lại: có quạt thật thì không được "dọn" nhầm.
    func testMenuKeepsFanControlsWhenAFanIsControllable() {
        let menu = NSMenu()
        let fan = FanReading(index: 0, rpm: 2400, target: 2400, min: 2317, max: 6800, forced: false)
        populate(menu, fans: [fan], target: DummyTarget())
        let titles = menu.items.map(\.title)

        XCTAssertNotNil(menu.items.first { $0.title == "Tất cả Auto" }, "menu: \(titles)")
        XCTAssertNotNil(menu.items.first { $0.title.hasPrefix("Quạt 1") }, "menu: \(titles)")
        XCTAssertNil(menu.items.first { $0.title.contains("không có quạt") },
                     "có quạt thì đừng hiện dòng báo không có; menu: \(titles)")
    }

}
