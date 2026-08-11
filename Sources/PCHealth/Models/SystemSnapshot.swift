import Foundation

/// One complete reading of the machine, produced by `SystemCollector` on a background queue
/// and published to the UI as an immutable value.
struct SystemSnapshot {
    var timestamp = Date()
    var cpu = CPUStats()
    var gpus: [GPUStats] = []
    var memory = MemoryStats()
    var volumes: [VolumeStats] = []
    var diskIO = DiskIOStats()
    var network = NetworkStats()
    var power = PowerStats()
    /// Every temperature / voltage / current reading we could find, from all sources.
    var sensors: [Sensor] = []

    var isEmpty: Bool { sensors.isEmpty && cpu.cores.isEmpty }

    // MARK: - Derived temperatures

    func temperatures(in group: SensorGroup) -> [Sensor] {
        sensors.filter { $0.group == group && $0.kind == .temperature }
    }

    private func average(_ group: SensorGroup) -> Double? {
        let values = temperatures(in: group).map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func peak(_ group: SensorGroup) -> Double? {
        temperatures(in: group).map(\.value).max()
    }

    var cpuTemperature: Double? { average(.cpu) ?? average(.soc) }
    var cpuTemperaturePeak: Double? { peak(.cpu) ?? peak(.soc) }
    var gpuTemperature: Double? { average(.gpu) }
    var socTemperature: Double? { average(.soc) }
    var batteryTemperature: Double? { peak(.battery) ?? power.battery.temperature }
    var storageTemperature: Double? { peak(.storage) }

    var hottestSensor: Sensor? {
        sensors.filter { $0.kind == .temperature }.max { $0.value < $1.value }
    }

    var gpuUtilization: Double { gpus.first?.deviceUtilization ?? 0 }

    var sensorsByGroup: [(group: SensorGroup, sensors: [Sensor])] {
        SensorGroup.allCases.compactMap { group in
            let matching = sensors.filter { $0.group == group }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return matching.isEmpty ? nil : (group, matching)
        }
    }
}

/// Rolling series backing the charts.
struct SnapshotHistory {
    var cpuUsage = History()
    var cpuTemperature = History()
    var gpuUsage = History()
    var gpuTemperature = History()
    var memoryUsed = History()
    var networkDown = History()
    var networkUp = History()
    var diskRead = History()
    var diskWrite = History()
    var systemPower = History()
    var fanSpeed = History()

    mutating func append(_ snapshot: SystemSnapshot) {
        cpuUsage.push(snapshot.cpu.totalUsage)
        cpuTemperature.push(snapshot.cpuTemperature ?? 0)
        gpuUsage.push(snapshot.gpuUtilization)
        gpuTemperature.push(snapshot.gpuTemperature ?? 0)
        memoryUsed.push(snapshot.memory.usedPercent)
        networkDown.push(snapshot.network.totalDownload)
        networkUp.push(snapshot.network.totalUpload)
        diskRead.push(snapshot.diskIO.readBytesPerSecond)
        diskWrite.push(snapshot.diskIO.writeBytesPerSecond)
        systemPower.push(snapshot.power.systemPowerWatts ?? 0)
        fanSpeed.push(snapshot.power.fans.first?.current ?? 0)
    }
}
