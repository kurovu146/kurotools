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
    private let threshold: Double
    private let ttlSeconds: Int
    public private(set) var isManual = false
    public private(set) var lastTarget: Int = 0

    public init(commander: FanCommanding, threshold: Double, ttlSeconds: Int) {
        self.commander = commander; self.threshold = threshold; self.ttlSeconds = ttlSeconds
    }

    /// Clamp, remember, and send. Returns the actually-applied RPM.
    @discardableResult
    public func setTarget(rpm: Int, min: Int, max: Int) -> Int {
        let applied = clampRPM(rpm, min: min, max: max)
        _ = commander.send(.setTarget(rpm: applied, ttlSeconds: ttlSeconds))
        isManual = true; lastTarget = applied
        return applied
    }

    public func setAuto() {
        _ = commander.send(.setAuto)
        isManual = false
    }

    /// Called each refresh. Re-sends a heartbeat (setTarget) while manual to keep
    /// the daemon's TTL alive; auto-reverts to Auto on over-temp.
    /// Returns true if it auto-reverted this tick.
    @discardableResult
    public func tick(currentTempC: Double, currentlyForced: Bool) -> Bool {
        guard isManual else { return false }
        if currentTempC >= threshold {
            setAuto()
            return true
        }
        _ = commander.send(.setTarget(rpm: lastTarget, ttlSeconds: ttlSeconds))  // heartbeat
        return false
    }
}
