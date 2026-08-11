import Foundation

/// Thin wrapper around `sysctlbyname` for the handful of values we need.
enum Sysctl {

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    static func integer(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 { return Int(value) }

        var value32: Int32 = 0
        var size32 = MemoryLayout<Int32>.size
        if sysctlbyname(name, &value32, &size32, nil, 0) == 0 { return Int(value32) }

        return nil
    }

    static func swapUsage() -> (total: UInt64, used: UInt64, free: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (usage.xsu_total, usage.xsu_used, usage.xsu_avail)
    }
}

/// Static facts about the machine, read once at launch.
struct MachineInfo {
    let modelIdentifier: String
    let chipName: String
    let physicalCores: Int
    let logicalCores: Int
    /// Efficiency / performance core split, when the CPU is heterogeneous (Apple silicon).
    let efficiencyCores: Int
    let performanceCores: Int
    let physicalMemory: UInt64
    let osVersion: String
    let isAppleSilicon: Bool

    static let current: MachineInfo = {
        let brand = Sysctl.string("machdep.cpu.brand_string") ?? "Unknown CPU"
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif

        // perflevel0 is the fastest cluster (P-cores) on Apple silicon.
        let p = Sysctl.integer("hw.perflevel0.physicalcpu") ?? 0
        let e = Sysctl.integer("hw.perflevel1.physicalcpu") ?? 0

        let os = ProcessInfo.processInfo.operatingSystemVersion
        return MachineInfo(
            modelIdentifier: Sysctl.string("hw.model") ?? "Mac",
            chipName: brand,
            physicalCores: Sysctl.integer("hw.physicalcpu") ?? 0,
            logicalCores: Sysctl.integer("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount,
            efficiencyCores: e,
            performanceCores: p,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            isAppleSilicon: appleSilicon
        )
    }()

    var coreSummary: String {
        if performanceCores > 0 && efficiencyCores > 0 {
            return "\(performanceCores)P + \(efficiencyCores)E · \(logicalCores) threads"
        }
        return "\(physicalCores) cores · \(logicalCores) threads"
    }
}
