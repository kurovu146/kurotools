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

/// "Used" matches Activity Monitor's "Memory Used":
/// App Memory (internal/anonymous − purgeable) + wired + compressed.
/// (The old `active`-based formula under-counted anonymous memory and didn't match Activity Monitor.)
public func memoryUsed(internalPages: UInt64, purgeablePages: UInt64,
                       wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
    let appMemory = internalPages > purgeablePages ? internalPages - purgeablePages : 0
    return (appMemory + wired + compressed) * pageSize
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
        let used = memoryUsed(internalPages: UInt64(stats.internal_page_count),
                              purgeablePages: UInt64(stats.purgeable_count),
                              wired: UInt64(stats.wire_count),
                              compressed: UInt64(stats.compressor_page_count),
                              pageSize: pageSize)
        return MemoryInfo(usedBytes: used, totalBytes: total)
    }
}
