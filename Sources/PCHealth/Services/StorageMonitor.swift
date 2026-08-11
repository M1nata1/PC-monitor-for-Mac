import Foundation
import IOKit

struct VolumeStats: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let total: UInt64
    let free: UInt64
    var used: UInt64 { total > free ? total - free : 0 }
    var usedPercent: Double { total == 0 ? 0 : Double(used) / Double(total) * 100 }
    let isRemovable: Bool
}

struct DiskIOStats {
    var readBytesPerSecond: Double = 0
    var writeBytesPerSecond: Double = 0
    var totalRead: UInt64 = 0
    var totalWritten: UInt64 = 0
}

/// Volume capacities from URL resource values, plus aggregate disk throughput from the
/// `IOBlockStorageDriver` statistics dictionary.
final class StorageMonitor {

    private var previousRead: UInt64?
    private var previousWrite: UInt64?
    private var previousTimestamp: Date?

    func volumes() -> [VolumeStats] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsRemovableKey,
            .volumeIsBrowsableKey, .volumeIsInternalKey
        ]

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        var result: [VolumeStats] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }

            // The "important usage" figure matches what Finder reports (purgeable included).
            let free = values.volumeAvailableCapacityForImportantUsage.map { UInt64($0) }
                ?? UInt64(values.volumeAvailableCapacity ?? 0)

            result.append(VolumeStats(
                name: values.volumeName ?? url.lastPathComponent,
                path: url.path,
                total: UInt64(total),
                free: free,
                isRemovable: values.volumeIsRemovable ?? false
            ))
        }
        return result.sorted { $0.path == "/" && $1.path != "/" || $0.name < $1.name }
    }

    func io() -> DiskIOStats {
        var stats = DiskIOStats()
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == kIOReturnSuccess else { return stats }
        defer { IOObjectRelease(iterator) }

        while case let drive = IOIteratorNext(iterator), drive != 0 {
            defer { IOObjectRelease(drive) }
            guard let properties = IORegistryEntryCreateCFProperty(
                drive, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            if let read = properties["Bytes (Read)"] as? NSNumber { totalRead += read.uint64Value }
            if let write = properties["Bytes (Write)"] as? NSNumber { totalWrite += write.uint64Value }
        }

        stats.totalRead = totalRead
        stats.totalWritten = totalWrite

        let now = Date()
        if let previousRead, let previousWrite, let previousTimestamp {
            let interval = now.timeIntervalSince(previousTimestamp)
            if interval > 0 {
                stats.readBytesPerSecond = Double(totalRead &- previousRead) / interval
                stats.writeBytesPerSecond = Double(totalWrite &- previousWrite) / interval
            }
        }
        previousRead = totalRead
        previousWrite = totalWrite
        previousTimestamp = now

        return stats
    }
}
