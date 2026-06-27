import XCTest
@testable import SensorReader

final class SensorReaderTests: XCTestCase {
    func testModuleReady() {
        XCTAssertTrue(SensorReaderModule.ready)
    }
}
