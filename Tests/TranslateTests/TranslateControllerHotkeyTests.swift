import XCTest
import Carbon.HIToolbox
@testable import Translate

/// Bao phủ FIX 3/4 của round review đầu: `TranslateController` phải ghi lại
/// KẾT QUẢ THẬT của việc đăng ký hotkey, không giả định luôn thành công. Dùng
/// va chạm Carbon THẬT — đăng ký cùng (keyCode, modifiers) hai lần trong
/// cùng process, cái thứ hai trả `false` (lỗi `eventHotKeyExistsErr`, đã xác
/// nhận bằng thực nghiệm trước khi viết file này) — không mock: `HotkeyMonitor`
/// là `final class` bọc trực tiếp `RegisterEventHotKey`, không có chỗ nhét
/// test double mà không đổi cấu trúc controller (fix round 1 yêu cầu KHÔNG
/// restructure).
///
/// Đi qua `registerHotkey(_:)` (internal, lộ ra qua `@testable`) thay vì gọi
/// `start(dbPath:)` đầy đủ — `start()` còn mở `KTranslateBridge.shared`, một
/// singleton cấp process mà các file test khác (StoreMaintenanceTests,
/// BridgeSmokeTests) đã chia sẻ và tự dọn dẹp riêng (Task 6 ruling); gọi nó
/// từ đây sẽ đụng store dùng chung ngoài phạm vi của fix này. Không test nào
/// ở đây chạm `HotkeyPreference.save`/`UserDefaults.standard`.
@MainActor
final class TranslateControllerHotkeyTests: XCTestCase {
    func testRegisterHotkeySucceedsWhenNothingElseOwnsTheCombo() {
        let combo = HotkeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey))
        let controller = TranslateController()

        let registered = controller.registerHotkey(combo)

        XCTAssertTrue(registered)
        XCTAssertEqual(controller.currentHotkey, combo)
        XCTAssertTrue(controller.isHotkeyRegistered)

        // Đối chứng dương: combo phải THẬT SỰ đang sống với hệ thống, không
        // chỉ một cờ Bool nói suông — đăng ký lại từ bên ngoài phải va.
        let intruder = HotkeyMonitor(keyCode: combo.keyCode, modifiers: combo.modifiers) {}
        XCTAssertFalse(intruder.register())
    }

    /// 🔑 Đúng bug FIX 3: app khác đã chiếm combo là chuyện thường, không cần
    /// race. Trước bản vá, `currentHotkey` được gán TRƯỚC khi biết
    /// `register()` thất bại và không hề có tín hiệu nào khác để UI biết
    /// combo đó KHÔNG hoạt động — UI sẽ nói dối ngay từ lần chạy đầu.
    func testRegisterHotkeyReportsUnregisteredWhenAnotherOwnerHoldsTheCombo() {
        let combo = HotkeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey))
        let occupier = HotkeyMonitor(keyCode: combo.keyCode, modifiers: combo.modifiers) {}
        defer { occupier.unregister() }
        XCTAssertTrue(occupier.register(), "setup: occupier phải chiếm được combo trước")

        let controller = TranslateController()
        let registered = controller.registerHotkey(combo)

        XCTAssertFalse(registered)
        // `currentHotkey` vẫn phải là combo được YÊU CẦU (cấu hình), không
        // phải giá trị mặc định ban đầu — UI cần biết "đây là combo anh
        // chọn", `isHotkeyRegistered` mới là cờ nói nó có sống hay không.
        XCTAssertEqual(controller.currentHotkey, combo)
        XCTAssertFalse(controller.isHotkeyRegistered)
    }

    /// FIX 4 (nhánh khôi phục THÀNH CÔNG): `applyHotkey` phải đăng ký lại
    /// combo cũ khi combo mới bị chiếm, và ghi `isHotkeyRegistered` bằng kết
    /// quả THẬT của lần khôi phục đó — không giả định luôn đúng.
    ///
    /// Nhánh "khôi phục cũng thất bại" không có test tự động: nó đòi một bên
    /// thứ ba chiếm đúng combo cũ trong khoảng hẹp giữa `unregister()` và
    /// `register()` lại (vài lệnh C đồng bộ) — không có điểm móc nào để một
    /// test đơn-process chen vào đó một cách tất định mà không cần seam lớn
    /// hơn phạm vi round fix này cho phép (xem báo cáo, mục FIX 4).
    func testApplyHotkeyRestoresThePreviousComboWhenTheNewOneIsTaken() {
        let previous = HotkeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey))
        let taken = HotkeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey))

        let controller = TranslateController()
        XCTAssertTrue(controller.registerHotkey(previous), "setup: combo cũ phải đăng ký được trước")

        let occupier = HotkeyMonitor(keyCode: taken.keyCode, modifiers: taken.modifiers) {}
        defer { occupier.unregister() }
        XCTAssertTrue(occupier.register(), "setup: occupier phải chiếm được combo mới trước")

        let result = controller.applyHotkey(taken)

        XCTAssertFalse(result)
        XCTAssertEqual(controller.currentHotkey, previous)
        XCTAssertTrue(controller.isHotkeyRegistered)

        // Đối chứng dương: combo cũ phải THẬT SỰ sống lại, không chỉ cờ nói
        // suông — đăng ký nó từ bên ngoài phải va.
        let intruder = HotkeyMonitor(keyCode: previous.keyCode, modifiers: previous.modifiers) {}
        XCTAssertFalse(intruder.register())
    }
}
