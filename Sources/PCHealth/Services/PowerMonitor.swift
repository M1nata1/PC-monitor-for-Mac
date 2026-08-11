import Foundation
import IOKit
import IOKit.ps

struct FanStats: Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let current: Double
    let minimum: Double?
    let maximum: Double?
    let target: Double?

    /// Position of the current speed between the fan's min and max, 0…1.
    var normalized: Double {
        guard let minimum, let maximum, maximum > minimum else { return 0 }
        return min(1, max(0, (current - minimum) / (maximum - minimum)))
    }
}

struct BatteryStats {
    var isPresent: Bool = false
    var charge: Double = 0             // %
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var cycleCount: Int?
    var health: Double?                // % of design capacity
    var temperature: Double?           // °C
    var voltage: Double?               // V
    var amperage: Double?              // A (negative when discharging)
    var designCapacity: Int?
    var maxCapacity: Int?

    var powerWatts: Double? {
        guard let voltage, let amperage else { return nil }
        return voltage * amperage
    }
}

struct PowerStats {
    var battery = BatteryStats()
    var fans: [FanStats] = []
    var rails: [Sensor] = []           // SMC power / voltage / current keys
    var thermalPressure: String = "Nominal"

    /// Best available whole-machine power figure: total system draw if the SMC has it,
    /// otherwise what comes in over the charger, otherwise what the battery delivers.
    var systemPower: Sensor? {
        for key in ["PSTR", "PCPT", "PDTR", "PPBR"] {
            if let rail = rails.first(where: { $0.key == key }) { return rail }
        }
        return nil
    }

    var systemPowerWatts: Double? { systemPower?.value }
}

/// Battery, fans and the SMC power rails.
final class PowerMonitor {

    /// SMC keys worth showing, with human labels. Absent keys are skipped silently, so the
    /// same table works for Intel and Apple silicon.
    private static let powerKeys: [(key: String, label: String, kind: SensorKind)] = [
        ("PSTR", "System total", .power),
        ("PDTR", "DC in total", .power),
        ("PPBR", "Battery", .power),
        ("PHPC", "Heat pipe", .power),
        ("PC0C", "CPU core", .power),
        ("PCPC", "CPU package", .power),
        ("PCPG", "GPU (package)", .power),
        ("PCPT", "CPU total", .power),
        ("PG0R", "GPU rail", .power),
        ("PZ0S", "SoC", .power),
        ("VP0R", "12V rail", .voltage),
        ("VD0R", "DC in", .voltage),
        ("VG0C", "GPU core", .voltage),
        ("ID0R", "DC in", .current),
        ("IB0R", "Battery", .current)
    ]

    func sample() -> PowerStats {
        var stats = PowerStats()
        stats.battery = battery()
        stats.fans = fans()
        stats.rails = rails()
        stats.thermalPressure = PowerMonitor.thermalPressure()
        return stats
    }

    // MARK: - Fans

    private func fans() -> [FanStats] {
        let smc = SMC.shared
        guard smc.isAvailable, let count = smc.read("FNum").map({ Int($0) }), count > 0 else { return [] }

        return (0..<count).map { index in
            FanStats(
                index: index,
                current: smc.read("F\(index)Ac") ?? 0,
                minimum: smc.read("F\(index)Mn"),
                maximum: smc.read("F\(index)Mx"),
                target: smc.read("F\(index)Tg")
            )
        }
    }

    // MARK: - Power rails

    private func rails() -> [Sensor] {
        let smc = SMC.shared
        guard smc.isAvailable else { return [] }

        let values = smc.read(keys: PowerMonitor.powerKeys.map(\.key))
        return PowerMonitor.powerKeys.compactMap { entry in
            guard let value = values[entry.key], value.isFinite, value != 0 else { return nil }
            return Sensor(
                id: "smc:\(entry.key)",
                name: entry.label,
                group: .power,
                kind: entry.kind,
                source: .smc,
                value: value,
                key: entry.key
            )
        }
    }

    // MARK: - Battery

    private func battery() -> BatteryStats {
        var stats = BatteryStats()

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return stats }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

            stats.isPresent = true
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            stats.charge = maximum > 0 ? Double(current) / Double(maximum) * 100 : 0
            stats.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            stats.isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                stats.timeToEmptyMinutes = minutes
            }
            if let minutes = description[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                stats.timeToFullMinutes = minutes
            }
        }

        mergeSmartBatteryDetails(into: &stats)
        return stats
    }

    /// `AppleSmartBattery` carries the details IOPowerSources does not expose.
    private func mergeSmartBatteryDetails(into stats: inout BatteryStats) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0)
                == kIOReturnSuccess,
              let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else { return }

        stats.isPresent = stats.isPresent || (properties["BatteryInstalled"] as? Bool ?? false)
        stats.cycleCount = properties["CycleCount"] as? Int

        let design = properties["DesignCapacity"] as? Int
        let maximum = (properties["AppleRawMaxCapacity"] as? Int)
            ?? (properties["MaxCapacity"] as? Int)
        stats.designCapacity = design
        stats.maxCapacity = maximum
        if let design, design > 0, let maximum {
            stats.health = Double(maximum) / Double(design) * 100
        }

        if let temperature = properties["Temperature"] as? Int {
            stats.temperature = Double(temperature) / 100.0
        }
        if let voltage = properties["Voltage"] as? Int {
            stats.voltage = Double(voltage) / 1000.0
        }
        if let amperage = properties["Amperage"] as? Int {
            stats.amperage = Double(amperage) / 1000.0
        }
    }

    // MARK: - Thermal

    static func thermalPressure() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
