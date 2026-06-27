import XCTest
@testable import SystemStats

final class MemoryTests: XCTestCase {
    func testUsedBytesFromPages() {
        // Matches Activity Monitor "Memory Used" = App Memory (internal − purgeable) + wired + compressed.
        // internal=2000, purgeable=300 → appMemory=1700; +wired(500)+compressed(200) = 2400 pages.
        let used = memoryUsed(internalPages: 2000, purgeablePages: 300,
                              wired: 500, compressed: 200, pageSize: 16384)
        XCTAssertEqual(used, UInt64(2400) * 16384)
    }

    func testPurgeableClampedNoUnderflow() {
        // purgeable can't exceed internal in practice; guard against underflow anyway.
        let used = memoryUsed(internalPages: 100, purgeablePages: 999,
                              wired: 10, compressed: 5, pageSize: 16384)
        XCTAssertEqual(used, UInt64(15) * 16384)  // appMemory clamps to 0 → 0+10+5
    }

    func testGBConversion() {
        let info = MemoryInfo(usedBytes: 8 * 1_073_741_824, totalBytes: 16 * 1_073_741_824)
        XCTAssertEqual(info.usedGB, 8.0, accuracy: 0.001)
        XCTAssertEqual(info.usedPercent, 50.0, accuracy: 0.01)
    }
}
