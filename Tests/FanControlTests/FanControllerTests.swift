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

    func testTickSendsHeartbeatBelowThreshold() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        _ = fc.setTarget(rpm: 2000, min: 1800, max: 6000)
        spy.sent.removeAll()
        let reverted = fc.tick(currentTempC: 70, currentlyForced: true)
        XCTAssertFalse(reverted)
        XCTAssertEqual(spy.sent, [.setTarget(rpm: 2000, ttlSeconds: 6)])  // heartbeat keeps manual alive
    }

    func testSetAutoSends() {
        let spy = SpyCommander()
        let fc = FanController(commander: spy, threshold: 95, ttlSeconds: 6)
        fc.setAuto()
        XCTAssertEqual(spy.sent, [.setAuto])
    }

    func testFanCommandAndResponseCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // FanCommand round-trips
        let commands: [FanCommand] = [
            .setTarget(rpm: 3000, ttlSeconds: 6),
            .setAuto,
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
