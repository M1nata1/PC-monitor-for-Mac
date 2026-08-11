import Foundation
import Darwin

struct InterfaceStats: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let uploadBytesPerSecond: Double
    let downloadBytesPerSecond: Double
    let totalUpload: UInt64
    let totalDownload: UInt64
}

struct NetworkStats {
    var interfaces: [InterfaceStats] = []
    var totalUpload: Double = 0     // bytes/s across all interfaces
    var totalDownload: Double = 0
    var primaryInterface: String?
    var localAddress: String?
}

/// Byte counters per interface from `getifaddrs`, differenced between samples.
final class NetworkMonitor {

    private struct Counter { var input: UInt64; var output: UInt64 }

    private var previous: [String: Counter] = [:]
    private var previousTimestamp: Date?

    func sample() -> NetworkStats {
        var stats = NetworkStats()
        var current: [String: Counter] = [:]
        var addresses: [String: String] = [:]

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return stats }
        defer { freeifaddrs(head) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            guard let addr = interface.ifa_addr else { continue }

            switch Int32(addr.pointee.sa_family) {
            case AF_LINK:
                guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                current[name] = Counter(input: UInt64(data.pointee.ifi_ibytes),
                                        output: UInt64(data.pointee.ifi_obytes))
            case AF_INET:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host,
                               socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    addresses[name] = String(decoding: bytes, as: UTF8.self)
                }
            default:
                break
            }
        }

        let now = Date()
        let interval = previousTimestamp.map { now.timeIntervalSince($0) } ?? 0

        var interfaces: [InterfaceStats] = []
        for (name, counter) in current {
            // Loopback and utun tunnels double-count real traffic.
            guard !name.hasPrefix("lo"), !name.hasPrefix("utun"), !name.hasPrefix("gif"),
                  !name.hasPrefix("stf"), !name.hasPrefix("awdl"), !name.hasPrefix("llw") else { continue }

            var down = 0.0
            var up = 0.0
            if interval > 0, let old = previous[name] {
                down = Double(counter.input &- old.input) / interval
                up = Double(counter.output &- old.output) / interval
            }

            guard counter.input > 0 || counter.output > 0 else { continue }
            interfaces.append(InterfaceStats(
                name: name,
                uploadBytesPerSecond: max(0, up),
                downloadBytesPerSecond: max(0, down),
                totalUpload: counter.output,
                totalDownload: counter.input
            ))
        }

        previous = current
        previousTimestamp = now

        stats.interfaces = interfaces.sorted { $0.totalDownload > $1.totalDownload }
        stats.totalUpload = interfaces.reduce(0) { $0 + $1.uploadBytesPerSecond }
        stats.totalDownload = interfaces.reduce(0) { $0 + $1.downloadBytesPerSecond }
        stats.primaryInterface = stats.interfaces.first?.name
        stats.localAddress = stats.primaryInterface.flatMap { addresses[$0] }
            ?? addresses["en0"] ?? addresses.values.first

        return stats
    }
}
