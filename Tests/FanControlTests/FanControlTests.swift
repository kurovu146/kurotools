import XCTest
@testable import FanControl

final class FanControlTests: XCTestCase {
    func testModuleReady() {
        XCTAssertTrue(FanControlModule.ready)
    }
}
