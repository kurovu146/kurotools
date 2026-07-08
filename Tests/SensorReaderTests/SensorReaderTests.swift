import XCTest
@testable import SensorReader
@testable import SMCKit
import SystemStats

final class FakeSMC: SMCReading {
    var values: [String: SMCValue] = [:]
    var keys: [SMCKey] = []
    var readCounts: [String: Int] = [:]
    func read(_ key: SMCKey) throws -> SMCValue {
        readCounts[key.string, default: 0] += 1
        guard let v = values[key.string] else { throw SMCError.keyNotFound(key.string) }
        return v
    }
    func allKeys() throws -> [SMCKey] { keys }
}

final class SensorReaderTests: XCTestCase {

    func testMaxTempFiltersResidualAndOutliers() {
        // Power-gated P-cores report residual 0-8°C (below the 15°C floor);
        // 200 is an invalid outlier. Hottest valid sensor = 50.
        XCTAssertEqual(maxTemp([0, 6.7, 8.4, 40, 50, 200]), 50, accuracy: 0.01)
        // All sensors residual/invalid → 0 (no valid reading)
        XCTAssertEqual(maxTemp([6.7, 8.4]), 0, accuracy: 0.01)
        XCTAssertEqual(maxTemp([]), 0, accuracy: 0.01)
        // Exactly at the floor is still invalid; just above is valid
        XCTAssertEqual(maxTemp([15]), 0, accuracy: 0.01)
        XCTAssertEqual(maxTemp([15.1]), 15.1, accuracy: 0.01)
    }

    func testSnapshotReadsFanAndTemp() {
        let fake = FakeSMC()

        // Helper: encode a Double as little-endian flt SMCValue
        func flt(_ k: String, _ v: Double) -> SMCValue {
            let f = Float(v)
            let le = withUnsafeBytes(of: f) { Array($0) }
            return SMCValue(key: SMCKey(k), dataType: .flt, bytes: le)
        }

        // FNum=2 → two fans: F0Ac=2400, F1Ac=2600 → fanRPM should be max = 2600
        // Temp sensors: Tp01=44, Tp05=46 (P-core), Te05=48 (E-core),
        // Tp09=6.7 (power-gated residual, ignored) → hottest = 48
        fake.keys = [
            SMCKey("Tp01"), SMCKey("Tp05"), SMCKey("Te05"), SMCKey("Tp09"),
            SMCKey("FNum"),
            SMCKey("F0Ac"), SMCKey("F1Ac"),
            SMCKey("F0Tg"), SMCKey("F1Tg"),
            SMCKey("F0Mn"), SMCKey("F0Mx"), SMCKey("F0Md"),
            SMCKey("F1Mn"), SMCKey("F1Mx"), SMCKey("F1Md"),
        ]
        fake.values = [
            "Tp01": flt("Tp01", 44),
            "Tp05": flt("Tp05", 46),
            "Te05": flt("Te05", 48),
            "Tp09": flt("Tp09", 6.7),
            "FNum": SMCValue(key: SMCKey("FNum"), dataType: .ui8, bytes: [2]),
            "F0Ac": flt("F0Ac", 2400),
            "F1Ac": flt("F1Ac", 2600),
            "F0Tg": flt("F0Tg", 5000),   // fan 0 forced to a higher target than actual
            "F1Tg": flt("F1Tg", 2600),
            "F0Mn": flt("F0Mn", 2317),
            "F0Mx": flt("F0Mx", 6800),
            "F0Md": SMCValue(key: SMCKey("F0Md"), dataType: .ui8, bytes: [1]),
            "F1Mn": flt("F1Mn", 2317),
            "F1Mx": flt("F1Mx", 6800),
            "F1Md": SMCValue(key: SMCKey("F1Md"), dataType: .ui8, bytes: [0]),
        ]

        let r = SensorReader(smc: fake, cpu: CPULoadSampler(), mem: MemorySampler(),
                             tempKeyPrefixes: ["Tp", "Te"])
        let s = r.snapshot()

        // cpuTempC = hottest valid sensor = 48 (residual 6.7 ignored)
        XCTAssertEqual(s.cpuTempC, 48, accuracy: 0.01)
        // Two fans present
        XCTAssertEqual(s.fans.count, 2)
        XCTAssertEqual(s.fans[0].rpm, 2400, accuracy: 0.5)
        XCTAssertEqual(s.fans[1].rpm, 2600, accuracy: 0.5)
        // target (F{i}Tg) is read separately from actual (F{i}Ac)
        XCTAssertEqual(s.fans[0].target, 5000, accuracy: 0.5)
        XCTAssertEqual(s.fans[1].target, 2600, accuracy: 0.5)
        // fanRPM = max of fans = 2600
        XCTAssertEqual(s.fanRPM, 2600, accuracy: 0.5)
        XCTAssertEqual(s.fans[0].min, 2317, accuracy: 0.5)
        XCTAssertEqual(s.fans[0].max, 6800, accuracy: 0.5)
        // fan 0 is in forced mode (F0Md = 1), fan 1 is auto (F1Md = 0)
        XCTAssertTrue(s.fans[0].forced)
        XCTAssertFalse(s.fans[1].forced)
        // fanForced = true because at least one fan is forced
        XCTAssertTrue(s.fanForced)
    }

    func testSnapshotCachesStaticFanValues() {
        let fake = FakeSMC()
        func flt(_ k: String, _ v: Double) -> SMCValue {
            let f = Float(v)
            let le = withUnsafeBytes(of: f) { Array($0) }
            return SMCValue(key: SMCKey(k), dataType: .flt, bytes: le)
        }
        fake.keys = [SMCKey("Tp01")]
        fake.values = [
            "Tp01": flt("Tp01", 50),
            "FNum": SMCValue(key: SMCKey("FNum"), dataType: .ui8, bytes: [1]),
            "F0Ac": flt("F0Ac", 3000),
            "F0Tg": flt("F0Tg", 3000),
            "F0Mn": flt("F0Mn", 2317),
            "F0Mx": flt("F0Mx", 6800),
            "F0Md": SMCValue(key: SMCKey("F0Md"), dataType: .ui8, bytes: [0]),
        ]
        let r = SensorReader(smc: fake, cpu: CPULoadSampler(), mem: MemorySampler(),
                             tempKeyPrefixes: ["Tp"])
        _ = r.snapshot()
        let s = r.snapshot()

        // Static values (FNum, min, max) are read once and cached; only the
        // dynamic keys (Ac, Tg, Md) plus temps are re-read on every snapshot.
        XCTAssertEqual(fake.readCounts["FNum"], 1)
        XCTAssertEqual(fake.readCounts["F0Mn"], 1)
        XCTAssertEqual(fake.readCounts["F0Mx"], 1)
        XCTAssertEqual(fake.readCounts["F0Ac"], 2)
        XCTAssertEqual(fake.readCounts["F0Tg"], 2)
        XCTAssertEqual(fake.readCounts["F0Md"], 2)
        XCTAssertEqual(fake.readCounts["Tp01"], 2)
        // Cached statics still populate the snapshot correctly.
        XCTAssertEqual(s.fans[0].min, 2317, accuracy: 0.5)
        XCTAssertEqual(s.fans[0].max, 6800, accuracy: 0.5)
    }

    func testSnapshotFanRPMUsesMaxWhenOneZero() {
        let fake = FakeSMC()
        func flt(_ k: String, _ v: Double) -> SMCValue {
            let f = Float(v)
            let le = withUnsafeBytes(of: f) { Array($0) }
            return SMCValue(key: SMCKey(k), dataType: .flt, bytes: le)
        }
        // FNum missing → clamped to 1 → only fan 0
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
        XCTAssertEqual(s.fans.count, 1)
        XCTAssertEqual(s.fanRPM, 3000, accuracy: 0.5)
        XCTAssertFalse(s.fanForced)
    }
}
