import Foundation
import Darwin

struct CPUCoreLoad: Identifiable, Hashable {
    let id: Int
    let user: Double
    let system: Double
    let nice: Double
    var total: Double { user + system + nice }
}

struct CPUStats {
    var totalUsage: Double = 0
    var userUsage: Double = 0
    var systemUsage: Double = 0
    var idle: Double = 100
    var cores: [CPUCoreLoad] = []
    var loadAverage: (Double, Double, Double) = (0, 0, 0)
    var processCount: Int = 0
    var uptime: TimeInterval = 0
}

/// Per-core CPU load from `host_processor_info`, differenced between samples.
final class CPUMonitor {

    private var previousTicks: [[UInt32]] = []

    func sample() -> CPUStats {
        var stats = CPUStats()

        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return stats }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let stateCount = Int(CPU_STATE_MAX)
        var current: [[UInt32]] = []
        current.reserveCapacity(Int(cpuCount))

        for core in 0..<Int(cpuCount) {
            let base = core * stateCount
            let ticks = (0..<stateCount).map { UInt32(bitPattern: info[base + $0]) }
            current.append(ticks)
        }

        if previousTicks.count == current.count {
            var totalUser = 0.0, totalSystem = 0.0, totalNice = 0.0, totalIdle = 0.0

            for core in 0..<current.count {
                let delta = zip(current[core], previousTicks[core]).map { Double($0 &- $1) }
                let sum = delta.reduce(0, +)
                guard sum > 0 else {
                    stats.cores.append(CPUCoreLoad(id: core, user: 0, system: 0, nice: 0))
                    continue
                }
                let user = delta[Int(CPU_STATE_USER)] / sum * 100
                let system = delta[Int(CPU_STATE_SYSTEM)] / sum * 100
                let nice = delta[Int(CPU_STATE_NICE)] / sum * 100
                let idle = delta[Int(CPU_STATE_IDLE)] / sum * 100

                stats.cores.append(CPUCoreLoad(id: core, user: user, system: system, nice: nice))
                totalUser += user; totalSystem += system; totalNice += nice; totalIdle += idle
            }

            let coreCount = Double(max(current.count, 1))
            stats.userUsage = totalUser / coreCount
            stats.systemUsage = totalSystem / coreCount
            stats.idle = totalIdle / coreCount
            stats.totalUsage = min(100, (totalUser + totalSystem + totalNice) / coreCount)
        } else {
            stats.cores = (0..<current.count).map { CPUCoreLoad(id: $0, user: 0, system: 0, nice: 0) }
        }

        previousTicks = current

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            stats.loadAverage = (loads[0], loads[1], loads[2])
        }

        stats.processCount = CPUMonitor.processCount()
        stats.uptime = ProcessInfo.processInfo.systemUptime

        return stats
    }

    /// Number of live processes, from the size of the `KERN_PROC_ALL` table.
    private static func processCount() -> Int {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return 0 }
        return size / MemoryLayout<kinfo_proc>.stride
    }
}
