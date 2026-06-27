import XCTest
@testable import SystemStats

final class CPULoadTests: XCTestCase {
    func testUsageFromTickDelta() {
        let prev = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let curr = CPUTicks(user: 200, system: 100, idle: 1700, nice: 0)
        // busy delta = (100+50) = 150; total delta = 150 + 850 = 1000 -> 15%
        let pct = cpuUsagePercent(previous: prev, current: curr)
        XCTAssertEqual(pct, 15.0, accuracy: 0.01)
    }

    func testZeroDeltaIsZero() {
        let t = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertEqual(cpuUsagePercent(previous: t, current: t), 0, accuracy: 0.01)
    }
}
