import Foundation
import SMCKit
import SystemStats

// MARK: - FanReading

public struct FanReading: Equatable {
    public let index: Int
    /// Current actual speed (F{i}Ac) — lags the target while the fan spins up/down.
    public let rpm: Double
    /// Requested target speed (F{i}Tg) — reflects a manual set immediately.
    public let target: Double
    public let min: Double
    public let max: Double
    public let forced: Bool
    public init(index: Int, rpm: Double, target: Double, min: Double, max: Double, forced: Bool) {
        self.index = index
        self.rpm = rpm
        self.target = target
        self.min = min
        self.max = max
        self.forced = forced
    }
}

// MARK: - Snapshot

public struct Snapshot {
    public let cpuTempC: Double
    public let cpuLoadPct: Double
    public let ramUsedGB: Double
    public let ramTotalGB: Double
    public let fans: [FanReading]

    public init(cpuTempC: Double, cpuLoadPct: Double, ramUsedGB: Double, ramTotalGB: Double,
                fans: [FanReading]) {
        self.cpuTempC = cpuTempC
        self.cpuLoadPct = cpuLoadPct
        self.ramUsedGB = ramUsedGB
        self.ramTotalGB = ramTotalGB
        self.fans = fans
    }

    /// Loudest fan RPM (for the compact menu-bar readout).
    public var fanRPM: Double { fans.map(\.rpm).max() ?? 0 }

    /// True if any fan is in forced/manual mode.
    public var fanForced: Bool { fans.contains { $0.forced } }
}

// MARK: - Helpers

/// Hottest valid temp: filters out values <= 15 or >= 120.
/// Power-gated idle P-cores report residual 0-8°C on Apple Silicon — below
/// ambient, so anything under 15°C cannot be a real die temp. Returns 0 if
/// no valid values remain.
public func maxTemp(_ values: [Double]) -> Double {
    values.filter { $0 > 15 && $0 < 120 }.max() ?? 0
}

// MARK: - SensorReader

public final class SensorReader {
    private let smc: SMCReading
    private let cpu: CPULoadSampler
    private let mem: MemorySampler
    private let tempKeyPrefixes: [String]
    /// Cached after first allKeys() call — SMC key list doesn't change at runtime.
    private var cachedTempKeys: [SMCKey]?

    /// Per-fan constants resolved once: fan count (FNum), min/max RPM, and the
    /// SMCKey structs for the three per-tick reads. None of these change during
    /// a boot session, so re-reading them (and re-building key strings) every
    /// snapshot only added IOKit calls.
    private struct FanConstants {
        let acKey: SMCKey   // F{i}Ac — actual rpm
        let tgKey: SMCKey   // F{i}Tg — target rpm
        let mdKey: SMCKey   // F{i}Md — forced/auto mode
        let min: Double
        let max: Double
    }
    private var cachedFanConstants: [FanConstants]?

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

    private func fanConstants() -> [FanConstants] {
        if let cached = cachedFanConstants { return cached }
        // Chỉ nhận quạt đã tự chứng minh là có thật — xem `controllableFans()`.
        // Máy không quạt trả về mảng rỗng, và mảng rỗng đi thẳng ra `Snapshot.fans`
        // để menu biết mà bỏ hẳn phần điều khiển quạt thay vì hiện số 0.
        let constants = smc.controllableFans().map { fan in
            let i = fan.index
            return FanConstants(acKey: SMCKey("F\(i)Ac"),
                                tgKey: SMCKey("F\(i)Tg"),
                                mdKey: SMCKey("F\(i)Md"),
                                min: readDouble(SMCKey("F\(i)Mn")),
                                max: fan.maxRPM)
        }
        cachedFanConstants = constants
        return constants
    }

    // MARK: Public API

    public func snapshot() -> Snapshot {
        let temps = tempKeys().map { readDouble($0) }
        let m = mem.read()

        let fans = fanConstants().enumerated().map { (i, c) in
            FanReading(index: i,
                       rpm:    readDouble(c.acKey),
                       target: readDouble(c.tgKey),
                       min:    c.min,
                       max:    c.max,
                       forced: readDouble(c.mdKey) >= 0.5)
        }

        return Snapshot(
            cpuTempC:   maxTemp(temps),
            cpuLoadPct: cpu.usage(),
            ramUsedGB:  m.usedGB,
            ramTotalGB: m.totalGB,
            fans:       fans
        )
    }
}
