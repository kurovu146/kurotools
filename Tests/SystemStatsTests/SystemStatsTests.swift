import XCTest
@testable import SystemStats

final class SystemStatsTests: XCTestCase {
    func testModuleReady() {
        XCTAssertTrue(SystemStatsModule.ready)
    }
}
