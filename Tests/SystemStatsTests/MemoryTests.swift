import XCTest
@testable import SystemStats

final class MemoryTests: XCTestCase {
    func testUsedBytesFromPages() {
        // pageSize 16384 (Apple Silicon). active=1000, wired=500, compressed=200 pages.
        let used = memoryUsed(active: 1000, wired: 500, compressed: 200, pageSize: 16384)
        XCTAssertEqual(used, UInt64(1700) * 16384)
    }

    func testGBConversion() {
        let info = MemoryInfo(usedBytes: 8 * 1_073_741_824, totalBytes: 16 * 1_073_741_824)
        XCTAssertEqual(info.usedGB, 8.0, accuracy: 0.001)
        XCTAssertEqual(info.usedPercent, 50.0, accuracy: 0.01)
    }
}
