import Foundation

public struct MemoryInfo {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes; self.totalBytes = totalBytes
    }
    public var usedGB: Double { Double(usedBytes) / 1_073_741_824.0 }
    public var totalGB: Double { Double(totalBytes) / 1_073_741_824.0 }
    public var usedPercent: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100.0
    }
}

/// "Used" = active + wired + compressed (matches Activity Monitor's memory pressure footprint closely enough).
public func memoryUsed(active: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
    (active + wired + compressed) * pageSize
}

public final class MemorySampler {
    public init() {}

    public func read() -> MemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        guard kr == KERN_SUCCESS else { return MemoryInfo(usedBytes: 0, totalBytes: total) }
        let used = memoryUsed(active: UInt64(stats.active_count),
                              wired: UInt64(stats.wire_count),
                              compressed: UInt64(stats.compressor_page_count),
                              pageSize: pageSize)
        return MemoryInfo(usedBytes: used, totalBytes: total)
    }
}
