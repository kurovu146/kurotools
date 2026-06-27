import Foundation
import HelperProtocol

public protocol FanCommanding {
    func send(_ command: FanCommand) -> FanResponse
}

public func clampRPM(_ rpm: Int, min: Int, max: Int) -> Int {
    Swift.min(Swift.max(rpm, min), max)
}

public final class FanController {
    private let commander: FanCommanding
    private var threshold: Double
    private let ttlSeconds: Int
    private var manualTargets: [Int: Int] = [:]   // fan → last applied rpm

    public init(commander: FanCommanding, threshold: Double, ttlSeconds: Int) {
        self.commander = commander; self.threshold = threshold; self.ttlSeconds = ttlSeconds
    }

    public func setThreshold(_ c: Double) { threshold = c }

    /// Clamp, remember, send. Returns (appliedRPM, response).
    @discardableResult
    public func setTarget(fan: Int, rpm: Int, min: Int, max: Int) -> (rpm: Int, response: FanResponse) {
        let applied = clampRPM(rpm, min: min, max: max)
        let r = commander.send(.setTarget(fan: fan, rpm: applied, ttlSeconds: ttlSeconds))
        if r.ok { manualTargets[fan] = applied }
        return (applied, r)
    }

    @discardableResult
    public func setAuto(fan: Int) -> FanResponse {
        let r = commander.send(.setAuto(fan: fan))
        manualTargets[fan] = nil
        return r
    }

    @discardableResult
    public func setAllAuto() -> FanResponse {
        let r = commander.send(.allAuto)
        manualTargets.removeAll()
        return r
    }

    /// Heartbeat each manual fan; over-temp → all Auto. Returns (reverted, response).
    @discardableResult
    public func tick(currentTempC: Double) -> (reverted: Bool, response: FanResponse?) {
        guard !manualTargets.isEmpty else { return (false, nil) }
        if currentTempC >= threshold {
            let r = setAllAuto()
            return (true, r)
        }
        for (fan, target) in manualTargets { _ = commander.send(.setTarget(fan: fan, rpm: target, ttlSeconds: ttlSeconds)) }
        return (false, nil)
    }
}
