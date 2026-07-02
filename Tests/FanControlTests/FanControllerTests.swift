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
        let (applied, _) = fc.setTarget(fan: 0, rpm: 9000, min: 1800, max: 6000)
        XCTAssertEqual(applied, 6000)
        XCTAssertEqual(spy.sent, [.setTarget(fan: 0, rpm: 6000, ttlSeconds: 6)])
    }

    func testTickAutoRevertsAboveThreshold() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setTarget(fan: 0, rpm: 2000, min: 1800, max: 6000)
        spy.sent.removeAll()
        XCTAssertTrue(fc.tick(currentTempC: 96).reverted)
        XCTAssertEqual(spy.sent, [.allAuto])
    }

    func testTickSendsHeartbeatBelowThreshold() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setTarget(fan: 0, rpm: 2000, min: 1800, max: 6000)
        spy.sent.removeAll()
        XCTAssertFalse(fc.tick(currentTempC: 70).reverted)
        XCTAssertEqual(spy.sent, [.setTarget(fan: 0, rpm: 2000, ttlSeconds: 6)])  // heartbeat keeps manual alive
    }

    func testSetAutoSends() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setAuto(fan: 0)
        XCTAssertEqual(spy.sent, [.setAuto(fan: 0)])
    }

    func testSetAllAutoSends() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setTarget(fan: 0, rpm: 3000, min: 1800, max: 6000)
        _ = fc.setTarget(fan: 1, rpm: 4000, min: 1800, max: 6800)
        spy.sent.removeAll()
        _ = fc.setAllAuto()
        XCTAssertEqual(spy.sent, [.allAuto])
    }

    func testHasManualTargetsTracksLifecycle() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        XCTAssertFalse(fc.hasManualTargets)
        _ = fc.setTarget(fan: 0, rpm: 3000, min: 1800, max: 6000)
        XCTAssertTrue(fc.hasManualTargets)
        _ = fc.setAuto(fan: 0)
        XCTAssertFalse(fc.hasManualTargets)
        _ = fc.setTarget(fan: 0, rpm: 3000, min: 1800, max: 6000)
        _ = fc.setAllAuto()
        XCTAssertFalse(fc.hasManualTargets)
    }

    func testFanCommandAndResponseCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // FanCommand round-trips
        let commands: [FanCommand] = [
            .setTarget(fan: 1, rpm: 3000, ttlSeconds: 6),
            .setAuto(fan: 0),
            .allAuto,
            .ping,
        ]
        for cmd in commands {
            let data = try encoder.encode(cmd)
            let decoded = try decoder.decode(FanCommand.self, from: data)
            XCTAssertEqual(decoded, cmd, "round-trip failed for \(cmd)")
        }

        // FanResponse round-trip
        let response = FanResponse(ok: true, message: "pong")
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(FanResponse.self, from: data)
        XCTAssertEqual(decoded, response)
    }
}
