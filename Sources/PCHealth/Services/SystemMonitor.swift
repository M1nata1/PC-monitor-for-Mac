import Foundation
import Combine

/// Owns every low-level reader and turns them into a `SystemSnapshot`.
/// Lives entirely on the sampling queue — never touched from the main thread, which is what
/// makes the `@unchecked Sendable` conformance safe.
final class SystemCollector: @unchecked Sendable {
    private let cpu = CPUMonitor()
    private let gpu = GPUMonitor()
    private let memory = MemoryMonitor()
    private let storage = StorageMonitor()
    private let network = NetworkMonitor()
    private let power = PowerMonitor()
    private let smcSensors = SMCSensorScanner()

    /// Volumes change rarely; re-read them every N samples instead of every tick.
    private var volumeCache: [VolumeStats] = []
    private var tick = 0

    /// - Parameter fullSensorScan: when false only temperatures are polled, which keeps a
    ///   sample around 40 ms instead of 120 ms. The full scan is used while the sensor list
    ///   is on screen.
    func collect(fullSensorScan: Bool = true) -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.timestamp = Date()
        snapshot.cpu = cpu.sample()
        snapshot.gpus = gpu.sample()
        snapshot.memory = memory.sample()
        snapshot.diskIO = storage.io()
        snapshot.network = network.sample()
        snapshot.power = power.sample()

        if tick % 15 == 0 || volumeCache.isEmpty {
            volumeCache = storage.volumes()
        }
        snapshot.volumes = volumeCache
        tick &+= 1

        let kinds: Set<SensorKind> = fullSensorScan
            ? [.temperature, .fan, .power, .voltage, .current]
            : [.temperature]
        var sensors = HIDSensors.shared.readAll(kinds: kinds)
        sensors.append(contentsOf: smcSensors.readAll(kinds: kinds))

        // Fans and GPU load are sensors too, as far as the sensor list is concerned.
        for fan in snapshot.power.fans {
            sensors.append(Sensor(id: "fan:\(fan.index)", name: "Fan \(fan.index + 1)",
                                  group: .fans, kind: .fan, source: .smc,
                                  value: fan.current, key: "F\(fan.index)Ac"))
        }
        for (index, unit) in snapshot.gpus.enumerated() {
            sensors.append(Sensor(id: "gpu:\(index):util", name: "\(unit.name) utilization",
                                  group: .gpu, kind: .percentage, source: .ioreg,
                                  value: unit.deviceUtilization, key: nil))
        }

        // A machine can expose the same reading twice (HID + SMC); keep one per id.
        var seen = Set<String>()
        snapshot.sensors = sensors.filter { seen.insert($0.id).inserted }

        return snapshot
    }
}

/// Observable façade for the UI: samples on a timer, publishes snapshots and history.
@MainActor
final class SystemMonitor: ObservableObject {

    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var history = SnapshotHistory()
    @Published private(set) var isRunning = false
    @Published var refreshInterval: TimeInterval = 2 {
        didSet {
            guard refreshInterval != oldValue, isRunning else { return }
            restart()
        }
    }
    /// Set by the views that actually display every rail; keeps idle sampling cheap.
    @Published var fullSensorScan = false {
        didSet { scanMode.value = fullSensorScan }
    }

    /// Bridges `fullSensorScan` to the sampling queue, which cannot touch main-actor state.
    private final class ScanMode: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = false
        var value: Bool {
            get { lock.withLock { storage } }
            set { lock.withLock { storage = newValue } }
        }
    }
    private nonisolated let scanMode = ScanMode()

    let machine = MachineInfo.current
    var sensorSources: String {
        var parts: [String] = []
        if HIDSensors.shared.isAvailable { parts.append("IOHIDEventSystem") }
        if SMC.shared.isAvailable { parts.append("AppleSMC") }
        return parts.isEmpty ? "unavailable" : parts.joined(separator: " + ")
    }

    private nonisolated let collector = SystemCollector()
    private nonisolated let queue = DispatchQueue(label: "com.pchealth.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?

    init() {}

    func start() {
        guard timer == nil else { return }
        isRunning = true

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 0.05, repeating: refreshInterval, leeway: .milliseconds(200))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let reading = self.collector.collect(fullSensorScan: self.scanMode.value)
            Task { @MainActor [weak self] in
                self?.apply(reading)
            }
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    /// One-shot refresh, used by the toolbar button while sampling is paused.
    func refreshOnce() {
        queue.async { [weak self] in
            guard let self else { return }
            let reading = self.collector.collect(fullSensorScan: self.scanMode.value)
            Task { @MainActor [weak self] in
                self?.apply(reading)
            }
        }
    }

    private func restart() {
        stop()
        start()
    }

    /// Internal rather than private so the screenshot renderer can feed it samples.
    func apply(_ reading: SystemSnapshot) {
        snapshot = reading
        history.append(reading)
    }
}
