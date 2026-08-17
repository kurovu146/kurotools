import XCTest
@testable import Settings
@testable import Translate

private final class SpyBackend: TranslateBackend {
    var calls: [String] = []
    func capture() -> CaptureOutcome { .empty }
    func lookup(_ text: String, completion: @escaping (Lookup) -> Void) {}
    func languages() -> [String] { [] }
    func recentLanguages() -> [String] { [] }
    func langConfig() -> LangConfig? { nil }
    func setLangConfig(source: String?, target: String, other: String) -> LangConfig? { nil }
    func hasAccessibility() -> Bool { true }
    func requestAccessibility() -> Bool { true }
    func ttsAvailable() -> Bool { false }
    func speak(_ text: String) {}
    func isSaved(_ word: String) -> Bool { false }
    func setSaved(_ word: String, saved: Bool) -> Bool { true }

    func clearHistory() -> Bool { calls.append("clearHistory"); return true }
    func clearSavedWords() -> Bool { calls.append("clearSaved"); return true }
    func closeStore() -> Bool { calls.append("close"); return true }
    func openStore(at dbPath: URL) -> Bool { calls.append("open"); return true }
}

final class DataResetTests: XCTestCase {
    private var tmp: URL!
    private var dbPath: URL!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        dbPath = tmp.appendingPathComponent("ktranslate.db")
        try Data("payload".utf8).write(to: dbPath)
        suiteName = "kurotools.reset.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tmp)
    }

    func testClearingHistoryTouchesNothingElse() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        defaults.set(42, forKey: "thresholdC")

        XCTAssertTrue(reset.perform(.history, dbPath: dbPath, bundleID: suiteName))

        XCTAssertEqual(backend.calls, ["clearHistory"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath.path))
        XCTAssertEqual(defaults.integer(forKey: "thresholdC"), 42)
    }

    func testClearingSavedWordsTouchesNothingElse() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        XCTAssertTrue(reset.perform(.savedWords, dbPath: dbPath, bundleID: suiteName))
        XCTAssertEqual(backend.calls, ["clearSaved"])
    }

    func testResettingEverythingDeletesTheFileReopensAndWipesPreferences() {
        let backend = SpyBackend()
        let reset = DataReset(backend: backend, defaults: defaults, fileManager: .default)
        defaults.set(42, forKey: "thresholdC")

        XCTAssertTrue(reset.perform(.everything, dbPath: dbPath, bundleID: suiteName))

        XCTAssertEqual(backend.calls, ["close", "open"],
                       "phải đóng trước khi xoá file rồi mở lại — thiếu bước mở lại thì app mất db")
        XCTAssertEqual(defaults.object(forKey: "thresholdC") as? Int, nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath.path),
                       "file cũ đã bị xoá; store mở lại sẽ dựng schema mới")
    }
}
