import Foundation

/// Discovers every numeric SMC key on the machine once, then reads the interesting ones
/// on each refresh. This is what fills the "All sensors" tab on Intel Macs (where the SMC
/// owns the thermal sensors) and adds fan/power keys on Apple silicon.
final class SMCSensorScanner {

    private struct Descriptor {
        let key: String
        let kind: SensorKind
        let group: SensorGroup
        let name: String
    }

    private var descriptors: [Descriptor] = []
    private var didScan = false

    /// Key prefixes worth polling. The first character of an SMC key encodes its domain.
    private static func kind(forKey key: String) -> SensorKind? {
        switch key.first {
        case "T": return .temperature
        case "F": return key.hasSuffix("Ac") || key.hasSuffix("Tg") ? .fan : nil
        case "P": return .power
        case "V": return .voltage
        case "I": return .current
        default: return nil
        }
    }

    private static let numericTypes: Set<String> = [
        "flt ", "ui8 ", "ui16", "ui32", "si8 ", "si16", "si32",
        "sp78", "sp87", "sp96", "spa5", "spb4", "spf0", "sp1e", "sp3c", "sp4b", "sp5a", "sp69",
        "fp1f", "fp2e", "fp3d", "fp4c", "fp5b", "fp6a", "fp79", "fp88", "fpa6", "fpc4", "fpe2"
    ]

    func scanIfNeeded() {
        guard !didScan else { return }
        didScan = true
        guard SMC.shared.isAvailable else { return }

        for key in SMC.shared.allKeys() {
            guard let kind = SMCSensorScanner.kind(forKey: key),
                  let type = SMC.shared.type(of: key),
                  SMCSensorScanner.numericTypes.contains(type) else { continue }

            descriptors.append(Descriptor(
                key: key,
                kind: kind,
                group: SMCSensorScanner.group(forKey: key, kind: kind),
                name: SMCSensorScanner.name(forKey: key)
            ))
        }
    }

    /// - Parameter kinds: limits the poll to the families the UI currently needs. Each key
    ///   costs an IOKit call, and a modern Mac exposes a few hundred of them.
    func readAll(kinds: Set<SensorKind> = [.temperature, .fan, .power, .voltage, .current]) -> [Sensor] {
        scanIfNeeded()
        let descriptors = self.descriptors.filter { kinds.contains($0.kind) }
        guard !descriptors.isEmpty else { return [] }

        let values = SMC.shared.read(keys: descriptors.map(\.key))
        return descriptors.compactMap { descriptor in
            guard let value = values[descriptor.key], value.isFinite else { return nil }
            // Unpopulated sensors read as 0 or as an obviously bogus temperature.
            if descriptor.kind == .temperature && (value <= 1 || value > 150) { return nil }
            if descriptor.kind != .temperature && value == 0 { return nil }

            return Sensor(
                id: "smc:\(descriptor.key)",
                name: descriptor.name,
                group: descriptor.group,
                kind: descriptor.kind,
                source: .smc,
                value: value,
                key: descriptor.key
            )
        }
    }

    // MARK: - Key naming

    /// Well-known keys get a readable label; everything else falls back to the raw key.
    private static let knownNames: [String: String] = [
        "TC0P": "CPU proximity",
        "TC0D": "CPU die",
        "TC0E": "CPU PECI",
        "TC0F": "CPU PECI (filtered)",
        "TC0H": "CPU heatsink",
        "TCAD": "CPU package",
        "TCXC": "CPU core (PECI)",
        "TG0P": "GPU proximity",
        "TG0D": "GPU die",
        "TG0H": "GPU heatsink",
        "TA0P": "Ambient",
        "TA1P": "Ambient 2",
        "Ta0P": "Airflow",
        "TB0T": "Battery",
        "TB1T": "Battery 2",
        "TB2T": "Battery 3",
        "TH0P": "Drive bay",
        "TN0D": "Northbridge die",
        "TN0P": "Northbridge proximity",
        "Tm0P": "Mainboard proximity",
        "Tp0P": "Power supply",
        "TW0P": "Wireless module",
        "Ts0P": "Palm rest",
        "Ts0S": "Skin",
        "TM0P": "Memory proximity",
        "TS0C": "Thermal sensor 0",
        "PSTR": "System total power",
        "PDTR": "DC in power",
        "PPBR": "Battery power",
        "PC0C": "CPU core power",
        "PCPG": "GPU package power",
        "PCPT": "CPU total power",
        "VP0R": "12V rail",
        "VD0R": "DC in voltage",
        "ID0R": "DC in current",
        "IB0R": "Battery current"
    ]

    private static func name(forKey key: String) -> String {
        if let known = knownNames[key] { return "\(known) (\(key))" }
        if key.first == "F" {
            let index = key.dropFirst().prefix(1)
            if key.hasSuffix("Ac") { return "Fan \(index) speed (\(key))" }
            if key.hasSuffix("Tg") { return "Fan \(index) target (\(key))" }
        }
        return key
    }

    private static func group(forKey key: String, kind: SensorKind) -> SensorGroup {
        if kind == .fan { return .fans }
        let prefix = key.prefix(2).uppercased()
        switch prefix {
        // "TC*" on Intel and Apple silicon, "Tp*" on M1/M2 (per-core die sensors).
        case "TC", "TP": return .cpu
        case "TG": return .gpu
        case "TB", "IB": return .battery
        case "TM": return .memory
        case "TH", "TN": return .storage
        case "TW": return .wireless
        case "TA", "TS", "TL": return .ambient
        default:
            return kind == .temperature ? .other : .power
        }
    }
}
