import Foundation

/// Reads the thermal / power sensors that Apple silicon exposes through `IOHIDEventSystem`.
///
/// These symbols are part of IOKit but are not in the public headers, so we resolve them at
/// runtime with `dlsym`. If any lookup fails (or the machine has no such sensors, e.g. Intel),
/// the reader simply reports nothing and the app falls back to the SMC.
final class HIDSensors {

    static let shared = HIDSensors()

    // MARK: - Private IOKit surface

    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject?, CFDictionary?) -> Void
    private typealias CopyServices = @convention(c) (AnyObject?) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject?, CFString?) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject?, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias EventGetFloat = @convention(c) (AnyObject?, Int32) -> Double

    private let createClient: CreateClient
    private let setMatching: SetMatching
    private let copyServices: CopyServices
    private let copyProperty: CopyProperty
    private let copyEvent: CopyEvent
    private let eventGetFloat: EventGetFloat

    private(set) var isAvailable = false

    /// HID usage pages/usages used by Apple's sensor services.
    private enum Usage {
        static let appleVendorPage = 0xff00
        static let temperatureSensor = 0x0005
        static let powerPage = 0xff08
        static let currentSensor = 0x0002
        static let voltageSensor = 0x0003
    }

    /// `IOHIDEventType` values; the field id for a type is `type << 16`.
    private enum EventType: Int64 {
        case temperature = 15
        case power = 25

        var fieldBase: Int32 { Int32(rawValue << 16) }
    }

    private struct Service {
        let client: AnyObject
        let name: String
        let eventType: EventType
        let kind: SensorKind
    }

    private var services: [Service] = []
    /// Keep the event-system clients alive for as long as their services are polled.
    private var clients: [AnyObject] = []
    private let lock = NSLock()

    private init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let matching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let servicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let property = dlsym(handle, "IOHIDServiceClientCopyProperty"),
              let event = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let floatValue = dlsym(handle, "IOHIDEventGetFloatValue")
        else {
            createClient = { _ in nil }
            setMatching = { _, _ in }
            copyServices = { _ in nil }
            copyProperty = { _, _ in nil }
            copyEvent = { _, _, _, _ in nil }
            eventGetFloat = { _, _ in 0 }
            return
        }

        createClient = unsafeBitCast(create, to: CreateClient.self)
        setMatching = unsafeBitCast(matching, to: SetMatching.self)
        copyServices = unsafeBitCast(servicesSym, to: CopyServices.self)
        copyProperty = unsafeBitCast(property, to: CopyProperty.self)
        copyEvent = unsafeBitCast(event, to: CopyEvent.self)
        eventGetFloat = unsafeBitCast(floatValue, to: EventGetFloat.self)

        discover()
        isAvailable = !services.isEmpty
    }

    // MARK: - Discovery

    private func discover() {
        let descriptors: [(page: Int, usage: Int, type: EventType, kind: SensorKind)] = [
            (Usage.appleVendorPage, Usage.temperatureSensor, .temperature, .temperature),
            (Usage.powerPage, Usage.currentSensor, .power, .current),
            (Usage.powerPage, Usage.voltageSensor, .power, .voltage)
        ]

        for descriptor in descriptors {
            guard let clientRef = createClient(kCFAllocatorDefault) else { continue }
            let client = clientRef.takeRetainedValue()
            clients.append(client)

            let matching: [String: Any] = [
                "PrimaryUsagePage": descriptor.page,
                "PrimaryUsage": descriptor.usage
            ]
            setMatching(client, matching as CFDictionary)
            guard let servicesRef = copyServices(client) else { continue }
            let found = servicesRef.takeRetainedValue() as [AnyObject]

            for service in found {
                let name = (copyProperty(service, "Product" as CFString)?
                    .takeRetainedValue() as? String) ?? "Unknown sensor"
                services.append(Service(client: service, name: name,
                                        eventType: descriptor.type, kind: descriptor.kind))
            }
        }
    }

    // MARK: - Reading

    /// - Parameter kinds: which sensor families to poll. Reading every voltage and current
    ///   rail costs an IOKit round-trip each, so the UI asks for temperatures only unless
    ///   the full sensor list is on screen.
    func readAll(kinds: Set<SensorKind> = [.temperature, .voltage, .current]) -> [Sensor] {
        lock.lock()
        defer { lock.unlock() }
        guard isAvailable else { return [] }

        var results: [Sensor] = []
        results.reserveCapacity(services.count)

        for service in services where kinds.contains(service.kind) {
            guard let eventRef = copyEvent(service.client, service.eventType.rawValue, 0, 0) else { continue }
            let event = eventRef.takeRetainedValue()
            let value = eventGetFloat(event, service.eventType.fieldBase)
            // Powered-down rails report either zero or a raw ADC code near 2^14; both are noise.
            guard value.isFinite, HIDSensors.isPlausible(value, kind: service.kind) else { continue }

            results.append(Sensor(
                id: "hid:\(service.kind.rawValue):\(service.name)",
                name: service.name,
                group: HIDSensors.group(for: service.name, kind: service.kind),
                kind: service.kind,
                source: .hid,
                value: value,
                key: nil
            ))
        }
        return results
    }

    /// Rails that are switched off answer with 0 or with a raw converter code (~2^14),
    /// which would otherwise show up as "16281 V". Keep only physically sensible readings.
    private static func isPlausible(_ value: Double, kind: SensorKind) -> Bool {
        switch kind {
        case .temperature: return value > 0 && value < 150
        case .voltage: return value > 0 && value < 60
        case .current: return value > 0 && value < 200
        default: return true
        }
    }

    // MARK: - Naming

    /// Apple's sensor names are terse ("pACC MTR Temp Sensor3", "gas gauge battery").
    /// Map them onto the groups the UI shows.
    static func group(for name: String, kind: SensorKind) -> SensorGroup {
        let lower = name.lowercased()

        // Voltage / current readings are power-domain data regardless of which block they feed.
        if kind == .voltage || kind == .current {
            return lower.contains("battery") || lower.contains("gas gauge") ? .battery : .power
        }

        if lower.contains("gpu") || lower.contains("agx") { return .gpu }
        if lower.contains("pacc") || lower.contains("eacc") || lower.contains("cpu") { return .cpu }
        if lower.contains("soc") || lower.contains("ane") || lower.contains("isp")
            || lower.contains("pmgr") || lower.contains("die") { return .soc }
        if lower.contains("nand") || lower.contains("ssd") || lower.contains("ans") { return .storage }
        if lower.contains("battery") || lower.contains("gas gauge") || lower.contains("charger") { return .battery }
        if lower.contains("wifi") || lower.contains("airport") || lower.contains("bluetooth") { return .wireless }
        if lower.contains("dram") || lower.contains("lpddr") || lower.contains("memory") { return .memory }
        if lower.contains("ambient") || lower.contains("skin") || lower.contains("tdev") { return .ambient }
        if lower.contains("pmu") { return .soc }

        return kind == .temperature ? .other : .power
    }

    /// Friendlier label for the dashboard.
    static func prettify(_ name: String) -> String {
        name
            .replacingOccurrences(of: "MTR Temp Sensor", with: "cluster")
            .replacingOccurrences(of: "pACC", with: "P-core")
            .replacingOccurrences(of: "eACC", with: "E-core")
            .replacingOccurrences(of: "  ", with: " ")
    }
}
