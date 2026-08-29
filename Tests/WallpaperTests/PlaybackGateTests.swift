import CoreGraphics
import XCTest
@testable import Wallpaper

/// Quyết định "có nên phát video hay không" — tách khỏi controller vì
/// controller dựng cửa sổ + AVPlayer thật, không chạy được trong test.
final class PlaybackGateTests: XCTestCase {

    // MARK: - shouldPlay

    func testPlaysWhenEnabledWithVideoVisibleAndOnPower() {
        XCTAssertTrue(PlaybackGate.shouldPlay(
            enabled: true, hasVideo: true, covered: false, onBattery: false))
    }

    func testDoesNotPlayWhenCovered() {
        XCTAssertFalse(PlaybackGate.shouldPlay(
            enabled: true, hasVideo: true, covered: true, onBattery: false))
    }

    func testDoesNotPlayOnBattery() {
        XCTAssertFalse(PlaybackGate.shouldPlay(
            enabled: true, hasVideo: true, covered: false, onBattery: true))
    }

    func testDoesNotPlayWhenDisabled() {
        XCTAssertFalse(PlaybackGate.shouldPlay(
            enabled: false, hasVideo: true, covered: false, onBattery: false))
    }

    func testDoesNotPlayWithoutVideo() {
        XCTAssertFalse(PlaybackGate.shouldPlay(
            enabled: true, hasVideo: false, covered: false, onBattery: false))
    }

    // MARK: - isCovered
    //
    // Toạ độ ở đây là toạ độ CGWindowBounds (gốc TRÊN-TRÁI), không phải
    // NSScreen.frame (gốc dưới-trái) — controller chịu trách nhiệm lật.

    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    private let desktopLayer = -2147483623

    private func window(layer: Int = 0, alpha: Double = 1.0, bounds: CGRect) -> ScreenWindow {
        ScreenWindow(layer: layer, alpha: alpha, bounds: bounds)
    }

    func testUncoveredWhenNothingOnScreen() {
        XCTAssertFalse(PlaybackGate.isCovered([], screenFrame: screen, aboveLayer: desktopLayer))
    }

    func testCoveredByOneFullScreenOpaqueWindow() {
        let w = window(bounds: screen)
        XCTAssertTrue(PlaybackGate.isCovered([w], screenFrame: screen, aboveLayer: desktopLayer))
    }

    /// Cửa sổ full-screen thật vẫn chừa menu bar — đo được 0.97 trên máy thật,
    /// nên ngưỡng phải bắt được nó.
    func testCoveredByWindowLeavingMenuBarGap() {
        let w = window(bounds: CGRect(x: 0, y: 37, width: 1800, height: 1132))
        XCTAssertTrue(PlaybackGate.isCovered([w], screenFrame: screen, aboveLayer: desktopLayer))
    }

    func testNotCoveredByHalfScreenWindow() {
        let w = window(bounds: CGRect(x: 0, y: 0, width: 900, height: 1169))
        XCTAssertFalse(PlaybackGate.isCovered([w], screenFrame: screen, aboveLayer: desktopLayer))
    }

    /// Cửa sổ gần trong suốt không che được gì — vẫn nhìn thấy video sau nó.
    func testNotCoveredByTransparentWindow() {
        let w = window(alpha: 0.2, bounds: screen)
        XCTAssertFalse(PlaybackGate.isCovered([w], screenFrame: screen, aboveLayer: desktopLayer))
    }

    /// Chính cửa sổ wallpaper (và mọi thứ dưới nó) không được tính là che.
    func testNotCoveredByWindowAtOrBelowWallpaperLayer() {
        let w = window(layer: desktopLayer, bounds: screen)
        XCTAssertFalse(PlaybackGate.isCovered([w], screenFrame: screen, aboveLayer: desktopLayer))
    }

    /// Hai cửa sổ nửa màn hình ghép lại che kín — nhưng ta cố tình KHÔNG cộng
    /// dồn: cộng diện tích rời rạc sẽ đếm trùng phần chồng nhau và báo che sai.
    /// Ghi lại lựa chọn này để lần sau không ai "sửa" nó thành cộng dồn.
    func testTwoHalfScreenWindowsDoNotCount() {
        let left = window(bounds: CGRect(x: 0, y: 0, width: 900, height: 1169))
        let right = window(bounds: CGRect(x: 900, y: 0, width: 900, height: 1169))
        XCTAssertFalse(PlaybackGate.isCovered([left, right],
                                              screenFrame: screen, aboveLayer: desktopLayer))
    }

    /// Cửa sổ trên màn hình khác không ảnh hưởng màn hình này.
    func testWindowOnAnotherScreenDoesNotCover() {
        let w = window(bounds: CGRect(x: 1800, y: 0, width: 1800, height: 1169))
        XCTAssertFalse(PlaybackGate.isCovered([w], screenFrame: screen, aboveLayer: desktopLayer))
    }

    // MARK: - parse

    func testParseReadsLayerAlphaAndBounds() throws {
        let infos: [[String: Any]] = [[
            "kCGWindowLayer": 0, "kCGWindowAlpha": 1.0,
            "kCGWindowBounds": ["X": 10.0, "Y": 20.0, "Width": 30.0, "Height": 40.0],
        ]]
        let parsed = PlaybackGate.parse(infos)
        let w = try XCTUnwrap(parsed.first)
        XCTAssertEqual(w.layer, 0)
        XCTAssertEqual(w.alpha, 1.0)
        XCTAssertEqual(w.bounds, CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    /// Entry thiếu trường phải bị bỏ qua chứ không làm hỏng cả lượt đo.
    func testParseSkipsEntriesMissingFields() {
        let infos: [[String: Any]] = [
            ["kCGWindowLayer": 0],
            ["kCGWindowAlpha": 1.0, "kCGWindowBounds": ["X": 0.0, "Y": 0.0]],
            [:],
        ]
        XCTAssertTrue(PlaybackGate.parse(infos).isEmpty)
    }

    // MARK: - Lật toạ độ
    //
    // NSScreen.frame có gốc DƯỚI-TRÁI của màn hình chính, y tăng lên.
    // CGWindowBounds có gốc TRÊN-TRÁI của màn hình chính, y tăng xuống.
    // Sai chỗ này thì trên một màn hình vẫn "đúng" nhờ đối xứng, chỉ lộ khi
    // cắm màn hình thứ hai — nên phải test đúng ca nhiều màn hình.

    func testFlipLeavesPrimaryScreenAtOrigin() {
        let primary = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        XCTAssertEqual(PlaybackGate.flip(primary, primaryTop: 1169),
                       CGRect(x: 0, y: 0, width: 1800, height: 1169))
    }

    /// Màn hình phụ đặt PHÍA TRÊN màn hình chính: trong toạ độ AppKit nó có y
    /// dương, sau khi lật phải thành y ÂM.
    func testFlipScreenAbovePrimaryBecomesNegativeY() {
        let above = CGRect(x: 0, y: 1169, width: 1920, height: 1080)
        XCTAssertEqual(PlaybackGate.flip(above, primaryTop: 1169),
                       CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    /// Màn hình phụ đặt PHÍA DƯỚI màn hình chính.
    func testFlipScreenBelowPrimaryBecomesPositiveY() {
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        XCTAssertEqual(PlaybackGate.flip(below, primaryTop: 1169),
                       CGRect(x: 0, y: 1169, width: 1920, height: 1080))
    }

    func testFlipKeepsXUntouched() {
        let right = CGRect(x: 1800, y: 0, width: 1920, height: 1169)
        XCTAssertEqual(PlaybackGate.flip(right, primaryTop: 1169).minX, 1800)
    }

    // MARK: - Nguồn điện

    func testBatteryPowerCountsAsOnBattery() {
        XCTAssertTrue(PlaybackGate.isOnBattery(powerSourceType: "Battery Power"))
    }

    func testACPowerIsNotOnBattery() {
        XCTAssertFalse(PlaybackGate.isOnBattery(powerSourceType: "AC Power"))
    }

    /// Chạy UPS nghĩa là điện lưới đã mất — tiết kiệm y như chạy pin.
    func testUPSPowerCountsAsOnBattery() {
        XCTAssertTrue(PlaybackGate.isOnBattery(powerSourceType: "UPS Power"))
    }

    /// Giá trị lạ (API đổi, máy không có pin) phải ngả về "không phải pin":
    /// đoán nhầm thành pin sẽ làm hình nền đứng hình mà người dùng không hiểu
    /// vì sao, còn đoán nhầm chiều kia chỉ tốn điện.
    func testUnknownPowerSourceIsNotTreatedAsBattery() {
        XCTAssertFalse(PlaybackGate.isOnBattery(powerSourceType: "Something Else"))
        XCTAssertFalse(PlaybackGate.isOnBattery(powerSourceType: ""))
    }
}
