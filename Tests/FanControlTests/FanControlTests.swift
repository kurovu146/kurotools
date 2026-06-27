import XCTest
@testable import FanControl
import HelperProtocol

final class SpyCommander: FanCommanding {
    var sent: [FanCommand] = []
    var nextResponse = FanResponse(ok: true, message: "ok")
    func send(_ command: FanCommand) -> FanResponse { sent.append(command); return nextResponse }
}

final class FanControllerTests: XCTestCase {
    func testClamp() {
        XCTAssertEqual(clampRPM(500, min: 1800, max: 6000), 1800)
        XCTAssertEqual(clampRPM(9000, min: 1800, max: 6000), 6000)
        XCTAssertEqual(clampRPM(3000, min: 1800, max: 6000), 3000)
    }

    func testSetTargetClampsAndSends() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        let applied = fc.setTarget(rpm: 9000, min: 1800, max: 6000)
        XCTAssertEqual(applied, 6000)
        XCTAssertEqual(spy.sent, [.setTarget(rpm: 6000, ttlSeconds: 6)])
    }

    func testTickAutoRevertsAboveThreshold() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setTarget(rpm: 2000, min: 1800, max: 6000)
        spy.sent.removeAll()
        let reverted = fc.tick(currentTempC: 96, currentlyForced: true)
        XCTAssertTrue(reverted)
        XCTAssertEqual(spy.sent, [.setAuto])
    }

    func testTickNoRevertBelowThreshold() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setTarget(rpm: 2000, min: 1800, max: 6000)
        spy.sent.removeAll()
        let reverted = fc.tick(currentTempC: 70, currentlyForced: true)
        XCTAssertFalse(reverted)
        XCTAssertTrue(spy.sent.isEmpty)
    }

    func testSetAutoSends() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        fc.setAuto()
        XCTAssertEqual(spy.sent, [.setAuto])
    }
}
