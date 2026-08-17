import XCTest
import TestSupport
import FanControl
import HelperProtocol
@testable import Vitals

/// Ghi lại lệnh mà `FanController` thực sự gửi qua `FanCommanding` — cùng
/// mẫu với `SpyCommander` trong `FanControlTests`.
private final class SpyCommander: FanCommanding {
    var sent: [FanCommand] = []
    func send(_ command: FanCommand) -> FanResponse {
        sent.append(command)
        return FanResponse(ok: true, message: "ok")
    }
}

@MainActor
final class VitalsSettingsApplyTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        (defaults, suiteName) = PreferencesSandbox.make("vitals")
    }

    override func tearDown() {
        PreferencesSandbox.destroy(suiteName)
    }

    /// Chứng minh ngưỡng THẬT SỰ tới `FanController` bằng hành vi quan sát
    /// được, không phải một property chỉ tồn tại để test đọc lại giá trị
    /// vừa gán (đọc lại kiểu đó chỉ chứng minh phép gán đã chạy, không
    /// chứng minh FanController đã được báo). `controller.fan` là chính
    /// instance mà `apply()` phải gọi `setThreshold` lên — không phải bản
    /// sao dựng riêng cho test.
    ///
    /// Đặt một manual target trước (điều kiện để `tick()` phát lệnh gì đó),
    /// rồi tick() ở 60°C: nằm GIỮA ngưỡng cũ 95 (không revert) và ngưỡng
    /// mới 50 (revert). Nếu `apply` quên đẩy ngưỡng mới xuống, `tick()` sẽ
    /// không phát `.allAuto` — test đỏ đúng bug mà brief mô tả (UI báo đã
    /// đổi trong khi quạt vẫn chạy theo ngưỡng cũ).
    func testApplyingASettingsChangePushesTheThresholdToTheFanController() {
        let spy = SpyCommander()
        let controller = VitalsController(defaults: defaults, fanCommanding: spy)
        var s = controller.currentSettings
        s.thresholdC = 50

        controller.apply(s)

        XCTAssertEqual(controller.currentSettings.thresholdC, 50)

        _ = controller.fan.setTarget(fan: 0, rpm: 2000, min: 1000, max: 3000)
        spy.sent.removeAll()

        let result = controller.fan.tick(currentTempC: 60)

        XCTAssertTrue(result.reverted,
            "60°C vượt ngưỡng MỚI (50) — nếu FanController vẫn giữ ngưỡng cũ (95) thì sẽ không revert")
        XCTAssertEqual(spy.sent, [.allAuto])
    }

    /// Đọc `.timeInterval` off chính `Timer` thật đang chạy — không phải
    /// một biến mirror có thể lệch khỏi timer thật.
    func testApplyingANewRefreshIntervalRestartsTheTimer() {
        let controller = VitalsController(defaults: defaults, fanCommanding: SpyCommander())
        var s = controller.currentSettings
        s.refreshSeconds = 3.0

        controller.apply(s)

        XCTAssertEqual(controller.currentSettings.refreshSeconds, 3.0)
        XCTAssertEqual(controller.timer?.timeInterval, 3.0,
            "timer phải chạy lại với nhịp mới, không giữ nhịp cũ tới lần khởi động sau")
    }

    /// Bao phủ vế còn lại của "một đường duy nhất": ghi UserDefaults, đúng
    /// vào suite test đã tiêm — không phải `.standard` thật của máy.
    func testApplyPersistsToTheInjectedDefaultsSuite() {
        let controller = VitalsController(defaults: defaults, fanCommanding: SpyCommander())
        var s = controller.currentSettings
        s.thresholdC = 77

        controller.apply(s)

        XCTAssertEqual(Settings.load(defaults: defaults).thresholdC, 77)
    }
}
