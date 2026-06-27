import XCTest
@testable import SensorReader
@testable import SMCKit
import SystemStats

final class FakeSMC: SMCReading {
    var values: [String: SMCValue] = [:]
    var keys: [SMCKey] = []
    func read(_ key: SMCKey) throws -> SMCValue {
        guard let v = values[key.string] else { throw SMCError.keyNotFound(key.string) }
        return v
    }
    func allKeys() throws -> [SMCKey] { keys }
}

final class SensorReaderTests: XCTestCase {

    func testAverageTempFiltersOutliers() {
        // 0 and 200 are invalid; average of 40 and 50 = 45
        XCTAssertEqual(averageTemp([0, 40, 50, 200]), 45, accuracy: 0.01)
        XCTAssertEqual(averageTemp([]), 0, accuracy: 0.01)
    }

    func testSnapshotReadsFanAndTemp() {
        let fake = FakeSMC()

        // Helper: encode a Double as little-endian flt SMCValue
        func flt(_ k: String, _ v: Double) -> SMCValue {
            let f = Float(v)
            let le = withUnsafeBytes(of: f) { Array($0) }
            return SMCValue(key: SMCKey(k), dataType: .flt, bytes: le)
        }

        // Two fans: F0Ac=2400, F1Ac=2600 → fanRPM should be max = 2600
        // Temp sensors: Tp01=44, Tp05=46 (P-core), Te05=48 (E-core) → avg = (44+46+48)/3 = 46
        fake.keys = [
            SMCKey("Tp01"), SMCKey("Tp05"), SMCKey("Te05"),
            SMCKey("F0Ac"), SMCKey("F1Ac"),
            SMCKey("F0Mn"), SMCKey("F0Mx"), SMCKey("F0Md"),
        ]
        fake.values = [
            "Tp01": flt("Tp01", 44),
            "Tp05": flt("Tp05", 46),
            "Te05": flt("Te05", 48),
            "F0Ac": flt("F0Ac", 2400),
            "F1Ac": flt("F1Ac", 2600),
            "F0Mn": flt("F0Mn", 2317),
            "F0Mx": flt("F0Mx", 6800),
            "F0Md": SMCValue(key: SMCKey("F0Md"), dataType: .ui8, bytes: [1]),
        ]

        let r = SensorReader(smc: fake, cpu: CPULoadSampler(), mem: MemorySampler(),
                             tempKeyPrefixes: ["Tp", "Te"])
        let s = r.snapshot()

        // cpuTempC = average of 44, 46, 48 = 46
        XCTAssertEqual(s.cpuTempC, 46, accuracy: 0.01)
        // fanRPM = max(F0Ac=2400, F1Ac=2600) = 2600
        XCTAssertEqual(s.fanRPM, 2600, accuracy: 0.5)
        XCTAssertEqual(s.fanMin, 2317, accuracy: 0.5)
        XCTAssertEqual(s.fanMax, 6800, accuracy: 0.5)
        XCTAssertTrue(s.fanForced)
    }

    func testSnapshotFanRPMUsesMaxWhenOneZero() {
        let fake = FakeSMC()
        func flt(_ k: String, _ v: Double) -> SMCValue {
            let f = Float(v)
            let le = withUnsafeBytes(of: f) { Array($0) }
            return SMCValue(key: SMCKey(k), dataType: .flt, bytes: le)
        }
        // Only F0Ac present, F1Ac missing → fanRPM = F0Ac
        fake.keys = [SMCKey("Tp01"), SMCKey("F0Ac"), SMCKey("F0Mn"), SMCKey("F0Mx"), SMCKey("F0Md")]
        fake.values = [
            "Tp01": flt("Tp01", 50),
            "F0Ac": flt("F0Ac", 3000),
            "F0Mn": flt("F0Mn", 2317),
            "F0Mx": flt("F0Mx", 6800),
            "F0Md": SMCValue(key: SMCKey("F0Md"), dataType: .ui8, bytes: [0]),
        ]
        let r = SensorReader(smc: fake, cpu: CPULoadSampler(), mem: MemorySampler(),
                             tempKeyPrefixes: ["Tp"])
        let s = r.snapshot()
        XCTAssertEqual(s.fanRPM, 3000, accuracy: 0.5)
        XCTAssertFalse(s.fanForced)
    }
}
