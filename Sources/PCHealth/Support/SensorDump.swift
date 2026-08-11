import Foundation

/// Headless mode: `PCHealth --dump [--json]` prints one reading and exits.
/// Handy for checking sensor availability over SSH or from a script.
enum SensorDump {

    /// `--bench`: how long a full sample takes, so the refresh interval stays honest.
    static func bench() {
        let collector = SystemCollector()
        for mode in [true, false] {
            print(mode ? "full scan (All sensors tab):" : "temperatures only (default):")
            for iteration in 1...4 {
                let start = DispatchTime.now()
                let snapshot = collector.collect(fullSensorScan: mode)
                let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                print(String(format: "  collect #%d: %6.1f ms  (%d sensors)",
                             iteration, milliseconds, snapshot.sensors.count))
            }
        }

        func time(_ label: String, _ body: () -> Int) {
            let start = DispatchTime.now()
            let count = body()
            let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            print(String(format: "  %-22@ %6.1f ms  (%d)", label as NSString, milliseconds, count))
        }

        let cpu = CPUMonitor(), gpu = GPUMonitor(), memory = MemoryMonitor()
        let storage = StorageMonitor(), network = NetworkMonitor(), power = PowerMonitor()
        let scanner = SMCSensorScanner()
        scanner.scanIfNeeded()

        time("cpu") { cpu.sample().cores.count }
        time("gpu") { gpu.sample().count }
        time("memory") { memory.sample().total > 0 ? 1 : 0 }
        time("disk io") { storage.io().totalRead > 0 ? 1 : 0 }
        time("volumes") { storage.volumes().count }
        time("network") { network.sample().interfaces.count }
        time("power+fans+rails") { power.sample().rails.count }
        time("hid sensors") { HIDSensors.shared.readAll().count }
        time("smc sensors") { scanner.readAll().count }
    }

    static func run(json: Bool) {
        let collector = SystemCollector()
        _ = collector.collect()          // prime the deltas (CPU load, I/O rates)
        Thread.sleep(forTimeInterval: 1.0)
        let snapshot = collector.collect()

        json ? printJSON(snapshot) : printText(snapshot)
    }

    private static func printText(_ snapshot: SystemSnapshot) {
        let machine = MachineInfo.current
        print("\(machine.chipName) — \(machine.modelIdentifier), macOS \(machine.osVersion)")
        print("\(machine.coreSummary), \(Format.bytes(machine.physicalMemory)) RAM")
        print("sources: HID=\(HIDSensors.shared.isAvailable) SMC=\(SMC.shared.isAvailable)")
        print("")

        print(String(format: "CPU     %5.1f%%  user %.1f%% sys %.1f%%  load %.2f",
                     snapshot.cpu.totalUsage, snapshot.cpu.userUsage,
                     snapshot.cpu.systemUsage, snapshot.cpu.loadAverage.0))
        for gpu in snapshot.gpus {
            print(String(format: "GPU     %5.1f%%  %@%@",
                         gpu.deviceUtilization, gpu.name,
                         gpu.coreCount.map { " (\($0) cores)" } ?? ""))
        }
        print(String(format: "Memory  %5.1f%%  %@ of %@ used, swap %@",
                     snapshot.memory.usedPercent, Format.bytes(snapshot.memory.used),
                     Format.bytes(snapshot.memory.total), Format.bytes(snapshot.memory.swapUsed)))
        print(String(format: "Disk    read %@  write %@",
                     Format.rate(snapshot.diskIO.readBytesPerSecond),
                     Format.rate(snapshot.diskIO.writeBytesPerSecond)))
        print(String(format: "Network down %@  up %@",
                     Format.rate(snapshot.network.totalDownload),
                     Format.rate(snapshot.network.totalUpload)))
        if snapshot.power.battery.isPresent {
            let battery = snapshot.power.battery
            print(String(format: "Battery %5.1f%%  %@%@",
                         battery.charge,
                         battery.isCharging ? "charging" : (battery.isPluggedIn ? "on AC" : "discharging"),
                         battery.health.map { String(format: ", health %.0f%%", $0) } ?? ""))
        }
        print("")

        for section in snapshot.sensorsByGroup {
            print("[\(section.group.rawValue)]")
            for sensor in section.sensors {
                let key = sensor.key.map { " (\($0))" } ?? ""
                print(String(format: "  %-42@ %12@  %@",
                             sensor.name + key as NSString,
                             sensor.formattedValue as NSString,
                             sensor.source.label))
            }
            print("")
        }

        if let hottest = snapshot.hottestSensor {
            print("Hottest: \(hottest.name) — \(hottest.formattedValue)")
        }
        print("Sensors found: \(snapshot.sensors.count)")
    }

    private static func printJSON(_ snapshot: SystemSnapshot) {
        var payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: snapshot.timestamp),
            "cpu": [
                "usage": snapshot.cpu.totalUsage,
                "user": snapshot.cpu.userUsage,
                "system": snapshot.cpu.systemUsage,
                "loadAverage": [snapshot.cpu.loadAverage.0,
                                snapshot.cpu.loadAverage.1,
                                snapshot.cpu.loadAverage.2],
                "temperature": snapshot.cpuTemperature as Any,
                "cores": snapshot.cpu.cores.map { ["core": $0.id, "usage": $0.total] }
            ],
            "gpu": snapshot.gpus.map {
                ["name": $0.name, "utilization": $0.deviceUtilization,
                 "cores": $0.coreCount as Any, "temperature": snapshot.gpuTemperature as Any]
            },
            "memory": [
                "total": snapshot.memory.total,
                "used": snapshot.memory.used,
                "usedPercent": snapshot.memory.usedPercent,
                "swapUsed": snapshot.memory.swapUsed
            ],
            "fans": snapshot.power.fans.map { ["index": $0.index, "rpm": $0.current] },
            "sensors": snapshot.sensors.map {
                ["name": $0.name, "key": $0.key as Any, "group": $0.group.rawValue,
                 "kind": $0.kind.rawValue, "unit": $0.kind.unit,
                 "value": $0.value, "source": $0.source.label]
            }
        ]
        if snapshot.power.battery.isPresent {
            payload["battery"] = [
                "charge": snapshot.power.battery.charge,
                "charging": snapshot.power.battery.isCharging,
                "health": snapshot.power.battery.health as Any,
                "cycles": snapshot.power.battery.cycleCount as Any
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print(text)
    }
}
