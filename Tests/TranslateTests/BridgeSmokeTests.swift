import XCTest
@testable import Translate

final class BridgeSmokeTests: XCTestCase {
    func testBridgeReachesTheRustCore() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertTrue(KTranslateBridge.shared.start(dbPath: dir.appendingPathComponent("t.db")))

        // Bảng ngôn ngữ nằm trong Rust — nhận được nó nghĩa là cầu thông suốt.
        let langs = KTranslateBridge.shared.languages()
        XCTAssertTrue(langs.contains("vi"), "expected the Rust language table, got \(langs.count) codes")

        let config = KTranslateBridge.shared.setLangConfig(source: "de", target: "vi", other: "en")
        XCTAssertEqual(config?.target, "vi")
    }
}
