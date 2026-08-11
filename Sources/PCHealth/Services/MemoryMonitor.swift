import Foundation
import Darwin

struct MemoryStats {
    var total: UInt64 = 0
    var app: UInt64 = 0          // "App Memory" in Activity Monitor
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0       // file-backed pages that can be evicted
    var free: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0

    var used: UInt64 { app + wired + compressed }
    var usedPercent: Double { total == 0 ? 0 : Double(used) / Double(total) * 100 }

    /// Activity Monitor's "memory pressure" heuristic: wired + compressed against total.
    var pressurePercent: Double {
        total == 0 ? 0 : Double(wired + compressed) / Double(total) * 100
    }
}

/// Physical memory breakdown from `host_statistics64(HOST_VM_INFO64)`.
final class MemoryMonitor {

    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    func sample() -> MemoryStats {
        var stats = MemoryStats()
        stats.total = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return stats }

        func bytes(_ pages: natural_t) -> UInt64 { UInt64(pages) * pageSize }

        let purgeable = bytes(vmStats.purgeable_count)
        let external = bytes(vmStats.external_page_count)
        let internalPages = bytes(vmStats.internal_page_count)

        stats.wired = bytes(vmStats.wire_count)
        stats.compressed = bytes(vmStats.compressor_page_count)
        stats.cached = external + purgeable
        stats.free = bytes(vmStats.free_count) >= bytes(vmStats.speculative_count)
            ? bytes(vmStats.free_count) - bytes(vmStats.speculative_count)
            : 0
        stats.app = internalPages > purgeable ? internalPages - purgeable : internalPages

        if let swap = Sysctl.swapUsage() {
            stats.swapTotal = swap.total
            stats.swapUsed = swap.used
        }

        return stats
    }
}
