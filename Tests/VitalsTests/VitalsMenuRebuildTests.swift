import XCTest
import TestSupport
import SensorReader
@testable import Vitals

@MainActor
final class VitalsMenuRebuildTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        (defaults, suiteName) = PreferencesSandbox.make("vitals-menu")
    }

    override func tearDown() {
        PreferencesSandbox.destroy(suiteName)
    }

    private func snapshot() -> Snapshot {
        Snapshot(cpuTempC: 40, cpuLoadPct: 10, ramUsedGB: 4, ramTotalGB: 16, fans: [])
    }

    /// 🔑 Nhãn của mục thêm mang trạng thái SỐNG (tổ hợp phím tra từ). Bản
    /// trước giữ `[NSMenuItem]` gán một lần lúc khởi động và chèn lại đúng
    /// object đó mãi mãi: đổi phím tắt trong Settings xong, cửa sổ hiện tổ hợp
    /// mới còn menu vẫn quảng cáo tổ hợp cũ tới lần khởi động sau.
    func testExtraItemsAreRebuiltOnEveryMenuUpdateNotFrozenAtLaunch() {
        let controller = VitalsController(defaults: defaults)
        var liveTitle = "Tra từ đang chọn  ⇧⌘D"
        var builds = 0
        controller.extraItemsProvider = {
            builds += 1
            return [NSMenuItem(title: liveTitle, action: nil, keyEquivalent: "")]
        }
        let menu = NSMenu()

        controller.rebuild(menu: menu, snapshot: snapshot())
        XCTAssertNotNil(menu.items.first { $0.title == "Tra từ đang chọn  ⇧⌘D" },
                        "lần mở đầu phải có mục tra từ; thấy: \(menu.items.map(\.title))")

        // Người dùng đổi phím tắt trong Settings giữa hai lần mở menu.
        liveTitle = "Tra từ đang chọn  ⌃⌥J"
        controller.rebuild(menu: menu, snapshot: snapshot())

        XCTAssertEqual(builds, 2, "provider phải được gọi lại mỗi lần menu dựng lại")
        XCTAssertNotNil(menu.items.first { $0.title == "Tra từ đang chọn  ⌃⌥J" },
                        "menu phải hiện tổ hợp MỚI; thấy: \(menu.items.map(\.title))")
        XCTAssertNil(menu.items.first { $0.title == "Tra từ đang chọn  ⇧⌘D" },
                     "nhãn cũ không được sống sót qua lần dựng lại; thấy: \(menu.items.map(\.title))")
    }

    /// Bất biến cũ vẫn phải giữ: mục thêm nằm TRƯỚC "Quit" (quy ước macOS giữ
    /// Quit ở cuối), và có một separator ngăn chúng khỏi thân menu.
    func testExtraItemsStayAboveQuit() throws {
        let controller = VitalsController(defaults: defaults)
        controller.extraItemsProvider = {
            [NSMenuItem(title: "Tra từ đang chọn  ⇧⌘D", action: nil, keyEquivalent: "")]
        }
        let menu = NSMenu()

        controller.rebuild(menu: menu, snapshot: snapshot())

        let titles = menu.items.map(\.title)
        let extra = try XCTUnwrap(titles.firstIndex(of: "Tra từ đang chọn  ⇧⌘D"),
                                  "thứ tự thật: \(titles)")
        let quit = try XCTUnwrap(titles.firstIndex(of: "Quit KuroTools"),
                                 "thứ tự thật: \(titles)")
        XCTAssertLessThan(extra, quit, "thứ tự thật: \(titles)")
    }
}
