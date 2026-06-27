import XCTest
@testable import KuroVitals
import SensorReader

final class FormatBarTests: XCTestCase {
    func testAllFields() {
        let s = Snapshot(cpuTempC: 48.4, cpuLoadPct: 12.6, ramUsedGB: 9.13,
                         ramTotalGB: 16, fanRPM: 2400, fanMin: 1800, fanMax: 6000, fanForced: false)
        var st = Settings(); st.showTemp = true; st.showCPU = true; st.showRAM = true; st.showFan = true
        XCTAssertEqual(formatBar(s, st), "48° 13% 9.1G 🌀2400")
    }

    func testSubsetFields() {
        let s = Snapshot(cpuTempC: 50, cpuLoadPct: 5, ramUsedGB: 8, ramTotalGB: 16,
                         fanRPM: 2000, fanMin: 1800, fanMax: 6000, fanForced: false)
        var st = Settings(); st.showTemp = true; st.showCPU = false; st.showRAM = false; st.showFan = true
        XCTAssertEqual(formatBar(s, st), "50° 🌀2000")
    }
}
