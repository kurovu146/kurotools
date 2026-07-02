import Foundation

public struct CPUTicks: Equatable {
    public let user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public func cpuUsagePercent(previous: CPUTicks, current: CPUTicks) -> Double {
    let userD = Double(current.user &- previous.user)
    let sysD  = Double(current.system &- previous.system)
    let niceD = Double(current.nice &- previous.nice)
    let idleD = Double(current.idle &- previous.idle)
    let busy = userD + sysD + niceD
    let total = busy + idleD
    guard total > 0 else { return 0 }
    return busy / total * 100.0
}

public final class CPULoadSampler {
    private var previous: CPUTicks?
    // Cached: every mach_host_self() call inserts another send-right reference
    // into the task's port namespace, which never gets released — a slow leak
    // in a process that samples 24/7.
    private let host = mach_host_self()

    public init() {}

    public func sample() -> CPUTicks {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return CPUTicks(user: 0, system: 0, idle: 0, nice: 0) }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3))
    }

    /// Returns usage since the previous call (0 on first call).
    public func usage() -> Double {
        let now = sample()
        defer { previous = now }
        guard let prev = previous else { return 0 }
        return cpuUsagePercent(previous: prev, current: now)
    }
}
