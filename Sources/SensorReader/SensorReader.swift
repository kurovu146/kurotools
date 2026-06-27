import Foundation
import SMCKit
import SystemStats

// MARK: - Snapshot

public struct Snapshot {
    public let cpuTempC: Double
    public let cpuLoadPct: Double
    public let ramUsedGB: Double
    public let ramTotalGB: Double
    /// RPM of the faster/louder fan (max of F0Ac and F1Ac).
    public let fanRPM: Double
    /// Minimum fan RPM (from F0Mn — both fans are symmetric on M2 Pro).
    public let fanMin: Double
    /// Maximum fan RPM (from F0Mx).
    public let fanMax: Double
    /// Whether fan is in forced/manual mode (F0Md >= 0.5).
    public let fanForced: Bool

    public init(cpuTempC: Double, cpuLoadPct: Double, ramUsedGB: Double, ramTotalGB: Double,
                fanRPM: Double, fanMin: Double, fanMax: Double, fanForced: Bool) {
        self.cpuTempC = cpuTempC
        self.cpuLoadPct = cpuLoadPct
        self.ramUsedGB = ramUsedGB
        self.ramTotalGB = ramTotalGB
        self.fanRPM = fanRPM
        self.fanMin = fanMin
        self.fanMax = fanMax
        self.fanForced = fanForced
    }
}

// MARK: - Helpers

/// Average of valid temps: filters out values <= 0 or >= 120 (invalid/outlier).
/// Returns 0 if no valid values remain.
public func averageTemp(_ values: [Double]) -> Double {
    let valid = values.filter { $0 > 0 && $0 < 120 }
    guard !valid.isEmpty else { return 0 }
    return valid.reduce(0, +) / Double(valid.count)
}

// MARK: - SensorReader

public final class SensorReader {
    private let smc: SMCReading
    private let cpu: CPULoadSampler
    private let mem: MemorySampler
    private let tempKeyPrefixes: [String]
    /// Cached after first allKeys() call — SMC key list doesn't change at runtime.
    private var cachedTempKeys: [SMCKey]?

    /// - Parameters:
    ///   - smc: SMC reader (real `SMC` or a mock for tests).
    ///   - cpu: CPU load sampler.
    ///   - mem: Memory sampler.
    ///   - tempKeyPrefixes: SMC key prefixes to treat as CPU temp sensors.
    ///     Defaults to `["Tp", "Te"]` — P-core and E-core sensors on M2 Pro.
    ///     (Tc* is empty, Tg* is GPU on M2 Pro — excluded by default.)
    public init(smc: SMCReading,
                cpu: CPULoadSampler,
                mem: MemorySampler,
                tempKeyPrefixes: [String] = ["Tp", "Te"]) {
        self.smc = smc
        self.cpu = cpu
        self.mem = mem
        self.tempKeyPrefixes = tempKeyPrefixes
    }

    // MARK: Private helpers

    private func tempKeys() -> [SMCKey] {
        if let cached = cachedTempKeys { return cached }
        let all = (try? smc.allKeys()) ?? []
        let matched = all.filter { key in
            tempKeyPrefixes.contains { key.string.hasPrefix($0) }
        }
        cachedTempKeys = matched
        return matched
    }

    private func readDouble(_ key: SMCKey) -> Double {
        (try? smc.read(key))?.double ?? 0
    }

    /// Fan RPM = max of F0Ac and F1Ac, ignoring any that are missing or zero.
    private func fanRPM() -> Double {
        let f0 = readDouble(SMCKey("F0Ac"))
        let f1 = readDouble(SMCKey("F1Ac"))
        let candidates = [f0, f1].filter { $0 > 0 }
        return candidates.max() ?? 0
    }

    // MARK: Public API

    public func snapshot() -> Snapshot {
        let temps = tempKeys().map { readDouble($0) }
        let m = mem.read()
        let fanMode = readDouble(SMCKey("F0Md"))

        return Snapshot(
            cpuTempC:   averageTemp(temps),
            cpuLoadPct: cpu.usage(),
            ramUsedGB:  m.usedGB,
            ramTotalGB: m.totalGB,
            fanRPM:     fanRPM(),
            fanMin:     readDouble(SMCKey("F0Mn")),
            fanMax:     readDouble(SMCKey("F0Mx")),
            fanForced:  fanMode >= 0.5
        )
    }
}
