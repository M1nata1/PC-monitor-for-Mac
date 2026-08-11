import Foundation
import SwiftUI

enum SensorKind: String, Codable, Hashable {
    case temperature
    case fan
    case power
    case voltage
    case current
    case percentage
    case raw

    var unit: String {
        switch self {
        case .temperature: return "°C"
        case .fan: return "RPM"
        case .power: return "W"
        case .voltage: return "V"
        case .current: return "A"
        case .percentage: return "%"
        case .raw: return ""
        }
    }

    var symbol: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .fan: return "fan"
        case .power: return "bolt.fill"
        case .voltage: return "bolt.horizontal"
        case .current: return "waveform.path.ecg"
        case .percentage: return "percent"
        case .raw: return "number"
        }
    }
}

enum SensorGroup: String, CaseIterable, Codable, Hashable {
    case cpu = "CPU"
    case gpu = "GPU"
    case soc = "SoC"
    case memory = "Memory"
    case storage = "Storage"
    case battery = "Battery"
    case power = "Power"
    case fans = "Fans"
    case wireless = "Wireless"
    case ambient = "Ambient"
    case other = "Other"

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .soc: return "square.grid.3x3.fill"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.100"
        case .power: return "bolt.circle"
        case .fans: return "fan"
        case .wireless: return "wifi"
        case .ambient: return "wind"
        case .other: return "sensor"
        }
    }

    var color: Color {
        switch self {
        case .cpu: return .blue
        case .gpu: return .purple
        case .soc: return .indigo
        case .memory: return .teal
        case .storage: return .green
        case .battery: return .mint
        case .power: return .yellow
        case .fans: return .cyan
        case .wireless: return .orange
        case .ambient: return .pink
        case .other: return .gray
        }
    }
}

enum SensorSource: String, Codable, Hashable {
    case hid = "HID"   // IOHIDEventSystem (Apple silicon thermal sensors)
    case smc = "SMC"   // AppleSMC keys
    case ioreg = "IOReg"

    var label: String { rawValue }
}

struct Sensor: Identifiable, Hashable {
    let id: String
    let name: String
    let group: SensorGroup
    let kind: SensorKind
    let source: SensorSource
    var value: Double
    /// Raw SMC key ("TC0P") when the reading came from the SMC.
    var key: String?

    var formattedValue: String {
        switch kind {
        case .temperature: return String(format: "%.1f°C", value)
        case .fan: return String(format: "%.0f RPM", value)
        case .power: return String(format: "%.2f W", value)
        case .voltage: return String(format: "%.3f V", value)
        case .current: return String(format: "%.3f A", value)
        case .percentage: return String(format: "%.0f%%", value)
        case .raw: return String(format: "%g", value)
        }
    }
}

// MARK: - Presentation helpers

extension Sensor {
    /// Colour ramp used for temperature readings across the UI.
    var severityColor: Color {
        guard kind == .temperature else { return .accentColor }
        return Sensor.temperatureColor(value)
    }

    static func temperatureColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<50: return .green
        case ..<70: return .yellow
        case ..<85: return .orange
        default: return .red
        }
    }

    static func loadColor(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return .green
        case ..<75: return .yellow
        case ..<90: return .orange
        default: return .red
        }
    }
}

enum TemperatureUnit: String, CaseIterable {
    case celsius = "°C"
    case fahrenheit = "°F"

    func convert(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    func format(_ celsius: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f\(rawValue)", convert(celsius))
    }
}

// MARK: - Rolling history for charts

struct History {
    private(set) var values: [Double] = []
    let limit: Int

    init(limit: Int = 120) {
        self.limit = limit
        values.reserveCapacity(limit)
    }

    mutating func push(_ value: Double) {
        values.append(value)
        if values.count > limit { values.removeFirst(values.count - limit) }
    }

    var last: Double { values.last ?? 0 }
    var peak: Double { values.max() ?? 0 }
    var average: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    /// Indexed points, oldest first, ready for Swift Charts.
    var points: [(index: Int, value: Double)] {
        values.enumerated().map { ($0.offset, $0.element) }
    }
}
