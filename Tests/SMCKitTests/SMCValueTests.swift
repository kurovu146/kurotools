import XCTest
@testable import SMCKit

final class SMCValueTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(SMCKit.version, "0.1.0")
    }
}
