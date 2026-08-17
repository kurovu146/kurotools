import XCTest
@testable import Translate

/// Chạy trên FFI THẬT với một db tạm — đây là chỗ duy nhất chứng minh bốn
/// hàm mới nối đúng sang Rust. Đặt tên có tiền tố `Store` để dễ lọc.
final class StoreMaintenanceTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testClearingSavedWordsThroughTheBridge() throws {
        let bridge = KTranslateBridge()
        // `STORE` phía Rust là global cho cả tiến trình test, và `kt_init` là
        // no-op thành công khi đã có store mở — không đóng trước thì test này
        // có thể lặng lẽ thao tác trên store một test KHÁC để lại (và tearDown
        // của test đó đã xoá luôn thư mục tmp bên dưới connection cũ).
        _ = bridge.closeStore()
        XCTAssertTrue(bridge.openStore(at: tmp.appendingPathComponent("a.db")))

        XCTAssertTrue(bridge.setSaved("ephemeral", saved: true))
        XCTAssertTrue(bridge.isSaved("ephemeral"))

        XCTAssertTrue(bridge.clearSavedWords())
        XCTAssertFalse(bridge.isSaved("ephemeral"))
    }

    func testReopeningAtANewPathStartsEmpty() throws {
        let bridge = KTranslateBridge()
        // Cùng lý do với test trên: đảm bảo store toàn cục đang đóng trước khi
        // mở "first.db", để phép thử reopen bên dưới không bị một store sót
        // lại từ test khác che mất.
        _ = bridge.closeStore()
        XCTAssertTrue(bridge.openStore(at: tmp.appendingPathComponent("first.db")))
        XCTAssertTrue(bridge.setSaved("in-first", saved: true))

        XCTAssertTrue(bridge.closeStore())
        XCTAssertTrue(bridge.openStore(at: tmp.appendingPathComponent("second.db")))

        XCTAssertFalse(bridge.isSaved("in-first"),
                       "db mới phải rỗng — nếu không, đổi chỗ db ghi vào file cũ trong im lặng")
    }
}
