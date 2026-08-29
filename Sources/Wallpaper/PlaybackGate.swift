import CoreGraphics
import IOKit.ps

/// Một cửa sổ đang hiện trên màn hình, rút gọn từ `CGWindowListCopyWindowInfo`.
public struct ScreenWindow: Equatable {
    public let layer: Int
    public let alpha: Double
    /// Toạ độ của CGWindowBounds: gốc TRÊN-TRÁI của màn hình chính, KHÁC
    /// `NSScreen.frame` (gốc dưới-trái). Người gọi phải lật trước khi so.
    public let bounds: CGRect

    public init(layer: Int, alpha: Double, bounds: CGRect) {
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }
}

/// Quyết định khi nào hình nền video được phép chạy.
///
/// 🔑 `NSWindow.occlusionState` KHÔNG dùng được ở đây. Đo trên macOS 26.5.2:
/// cùng MỘT cửa sổ, đặt ở desktop window level luôn báo `occluded` (kể cả khi
/// không có gì che và kể cả khi cửa sổ đục), đổi sang `.normal` thì báo
/// `VISIBLE`, trả về desktop level lại `occluded`. Cửa sổ hình nền sống ở
/// desktop level, nên nếu tin API đó thì video sẽ KHÔNG BAO GIỜ phát.
/// Vì vậy phải tự tính từ danh sách cửa sổ — đánh đổi là phải poll.
public enum PlaybackGate {
    /// Dưới ngưỡng này thì vẫn nhìn xuyên qua được, chưa coi là che.
    static let minAlpha = 0.95
    /// Cửa sổ full-screen thật vẫn chừa menu bar (đo được 0.97), nên ngưỡng
    /// phải thấp hơn 1.
    static let minCoverage = 0.95

    public static func shouldPlay(enabled: Bool, hasVideo: Bool,
                                  covered: Bool, onBattery: Bool) -> Bool {
        enabled && hasVideo && !covered && !onBattery
    }

    /// Chỉ xét TỪNG cửa sổ một, cố tình KHÔNG cộng dồn diện tích nhiều cửa sổ:
    /// phần chồng nhau sẽ bị đếm hai lần và báo "che" khi thực tế vẫn hở.
    /// Hệ quả đã biết: hai cửa sổ nửa màn hình ghép kín thì vẫn coi là không
    /// che — chấp nhận được, vì bỏ sót chỉ tốn điện, còn báo nhầm thì hình nền
    /// đứng hình trước mắt người dùng.
    public static func isCovered(_ windows: [ScreenWindow],
                                 screenFrame: CGRect, aboveLayer: Int) -> Bool {
        let area = screenFrame.width * screenFrame.height
        guard area > 0 else { return false }
        return windows.contains { w in
            guard w.layer > aboveLayer, w.alpha >= minAlpha else { return false }
            let overlap = w.bounds.intersection(screenFrame)
            guard !overlap.isNull else { return false }
            return (overlap.width * overlap.height) / area >= minCoverage
        }
    }

    /// Entry thiếu trường bị bỏ qua: danh sách cửa sổ là dữ liệu của hệ thống,
    /// một mục lạ không được làm hỏng cả lượt đo.
    public static func parse(_ infos: [[String: Any]]) -> [ScreenWindow] {
        infos.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let alpha = info[kCGWindowAlpha as String] as? Double,
                  let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? Double, let y = b["Y"] as? Double,
                  let w = b["Width"] as? Double, let h = b["Height"] as? Double
            else { return nil }
            return ScreenWindow(layer: layer, alpha: alpha,
                                bounds: CGRect(x: x, y: y, width: w, height: h))
        }
    }

    /// Lật `NSScreen.frame` (gốc dưới-trái, y tăng lên) sang hệ toạ độ của
    /// `CGWindowBounds` (gốc trên-trái của màn hình CHÍNH, y tăng xuống).
    /// `primaryTop` là `NSScreen.screens[0].frame.maxY`.
    public static func flip(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY,
               width: rect.width, height: rect.height)
    }

    /// Chạy pin hay chạy UPS đều là lúc phải tiết kiệm. Giá trị lạ ngả về
    /// `false`: đoán nhầm thành pin sẽ làm hình nền đứng hình khó hiểu, còn
    /// đoán nhầm chiều kia chỉ tốn điện.
    public static func isOnBattery(powerSourceType: String) -> Bool {
        powerSourceType == kIOPMBatteryPowerKey || powerSourceType == kIOPMUPSPowerKey
    }

    /// Đọc nguồn điện thật. Không test tất định được (phụ thuộc máy đang cắm
    /// sạc hay không) — phần phán quyết nằm ở `isOnBattery(powerSourceType:)`.
    public static func currentPowerSourceType() -> String {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue()
        else { return kIOPMACPowerKey }
        return type as String
    }
}
