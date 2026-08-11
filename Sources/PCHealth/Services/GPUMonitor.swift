import Foundation
import IOKit

struct GPUStats {
    var name: String = "GPU"
    var coreCount: Int?
    var deviceUtilization: Double = 0      // %
    var rendererUtilization: Double?       // %
    var tilerUtilization: Double?          // %
    var usedMemory: UInt64?                // bytes currently mapped
    var allocatedMemory: UInt64?           // bytes allocated from system memory
    var recoveryCount: Int?
}

/// Pulls the `PerformanceStatistics` dictionary that every graphics accelerator publishes
/// in the IORegistry. Works for the integrated Apple GPU, AMD/Intel discrete GPUs and eGPUs.
final class GPUMonitor {

    func sample() -> [GPUStats] {
        var results: [GPUStats] = []

        for entry in GPUMonitor.acceleratorEntries() {
            defer { IOObjectRelease(entry) }

            guard let statistics = IORegistryEntryCreateCFProperty(
                entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            var stats = GPUStats()
            stats.name = GPUMonitor.name(of: entry)
            stats.coreCount = GPUMonitor.number(entry, "gpu-core-count")

            stats.deviceUtilization = GPUMonitor.double(statistics,
                "Device Utilization %", "GPU Activity(%)", "GPU Core Utilization") ?? 0
            stats.rendererUtilization = GPUMonitor.double(statistics, "Renderer Utilization %")
            stats.tilerUtilization = GPUMonitor.double(statistics, "Tiler Utilization %")

            if let inUse = GPUMonitor.double(statistics, "In use system memory", "inUseVidMemoryBytes") {
                stats.usedMemory = UInt64(max(0, inUse))
            }
            if let allocated = GPUMonitor.double(statistics, "Alloc system memory", "allocatedVidMemoryBytes") {
                stats.allocatedMemory = UInt64(max(0, allocated))
            }
            if let recovery = GPUMonitor.double(statistics, "recoveryCount") {
                stats.recoveryCount = Int(recovery)
            }

            results.append(stats)
        }

        return results
    }

    // MARK: - IORegistry plumbing

    /// `IOAccelerator` covers Apple silicon (AGXAccelerator*) and older discrete GPUs;
    /// recent macOS releases also expose the newer `IOGPU` class.
    private static func acceleratorEntries() -> [io_registry_entry_t] {
        var entries: [io_registry_entry_t] = []

        for className in ["IOAccelerator", "IOGPU"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                               IOServiceMatching(className),
                                               &iterator) == kIOReturnSuccess else { continue }
            defer { IOObjectRelease(iterator) }

            while case let entry = IOIteratorNext(iterator), entry != 0 {
                // Skip duplicates: the same device can match both class names.
                if entries.contains(where: { IOObjectIsEqualTo($0, entry) != 0 }) {
                    IOObjectRelease(entry)
                    continue
                }
                entries.append(entry)
            }
            if !entries.isEmpty { break }
        }

        return entries
    }

    private static func name(of entry: io_registry_entry_t) -> String {
        // The accelerator's parent (the PCI/AGX device) carries the marketing name.
        var parent: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == kIOReturnSuccess {
            defer { IOObjectRelease(parent) }
            if let model = IORegistryEntryCreateCFProperty(parent, "model" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() {
                if let string = model as? String { return string }
                if let data = model as? Data {
                    let text = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
                    if !text.isEmpty { return text }
                }
            }
        }

        // io_name_t is a fixed 128-byte buffer.
        var nameBuffer = [CChar](repeating: 0, count: 128)
        if IORegistryEntryGetName(entry, &nameBuffer) == kIOReturnSuccess {
            let bytes = nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        }
        return "GPU"
    }

    private static func number(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        // Device-tree properties live on the accelerator's parent chain.
        var current = entry
        var owned = false
        for _ in 0..<4 {
            if let value = IORegistryEntryCreateCFProperty(current, key as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() {
                if owned { IOObjectRelease(current) }
                if let number = value as? Int { return number }
                if let data = value as? Data, data.count >= 4 {
                    return Int(data.withUnsafeBytes { $0.load(as: UInt32.self) })
                }
                return nil
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if owned { IOObjectRelease(current) }
            guard status == kIOReturnSuccess else { return nil }
            current = parent
            owned = true
        }
        if owned { IOObjectRelease(current) }
        return nil
    }

    private static func double(_ dictionary: [String: Any], _ keys: String...) -> Double? {
        for key in keys {
            if let number = dictionary[key] as? NSNumber { return number.doubleValue }
        }
        return nil
    }
}
