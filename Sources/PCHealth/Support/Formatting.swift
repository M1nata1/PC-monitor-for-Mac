import Foundation

enum Format {

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(clamping: value))
    }

    static func bytes(_ value: Double) -> String {
        bytes(UInt64(max(0, value)))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        "\(bytes(UInt64(max(0, bytesPerSecond))))/s"
    }

    static func percent(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", value)
    }

    static func watts(_ value: Double) -> String {
        String(format: "%.2f W", value)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func minutes(_ value: Int) -> String {
        value >= 60 ? "\(value / 60)h \(value % 60)m" : "\(value)m"
    }
}
