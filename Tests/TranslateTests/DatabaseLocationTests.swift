import XCTest
@testable import Translate

final class DatabaseLocationTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var tmp: URL!

    override func setUpWithError() throws {
        suiteName = "kurotools.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tmp)
    }

    func testWithoutAnOverrideItFallsBackToApplicationSupport() {
        let appSupport = tmp.appendingPathComponent("AppSupport")
        let resolved = DatabaseLocation.resolve(
            appSupport: appSupport, defaults: defaults, fileManager: .default)
        XCTAssertEqual(resolved.lastPathComponent, "ktranslate.db")
        XCTAssertTrue(resolved.path.contains("com.kurovu.kurotools"))
    }

    func testAnOverrideDirectoryIsUsed() throws {
        let custom = tmp.appendingPathComponent("custom")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: custom.appendingPathComponent("ktranslate.db").path, contents: Data())

        DatabaseLocation.setOverride(custom, defaults: defaults)
        let resolved = DatabaseLocation.resolve(
            appSupport: tmp.appendingPathComponent("AppSupport"),
            defaults: defaults, fileManager: .default)

        XCTAssertEqual(resolved, custom.appendingPathComponent("ktranslate.db"))
    }

    func testAnOverridePointingAtAVanishedFolderFallsBack() {
        // Ổ ngoài bị rút là chuyện bình thường. App phải khởi động được, không
        // phải chết vì một preference trỏ vào hư không.
        DatabaseLocation.setOverride(tmp.appendingPathComponent("gone"), defaults: defaults)
        let appSupport = tmp.appendingPathComponent("AppSupport")
        let resolved = DatabaseLocation.resolve(
            appSupport: appSupport, defaults: defaults, fileManager: .default)
        XCTAssertTrue(resolved.path.contains("com.kurovu.kurotools"))
    }

    func testClearingTheOverrideReturnsToTheDefault() {
        DatabaseLocation.setOverride(tmp, defaults: defaults)
        DatabaseLocation.setOverride(nil, defaults: defaults)
        XCTAssertNil(defaults.string(forKey: DatabaseLocation.overrideKey))
    }
}
