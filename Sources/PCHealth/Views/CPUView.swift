import SwiftUI

struct CPUView: View {
    @ObservedObject var monitor: SystemMonitor
    let unit: TemperatureUnit

    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ScrollView { content }
    }

    /// Split out of `body` so the screenshot renderer can draw the page without a
    /// scroll view — `ImageRenderer` renders a `ScrollView` as blank.
    @ViewBuilder
    var content: some View {
        VStack(spacing: 14) {
            Card("Processor", systemImage: "cpu", tint: .blue) {
                HStack(spacing: 14) {
                    RingGauge(
                        value: snapshot.cpu.totalUsage / 100,
                        label: Format.percent(snapshot.cpu.totalUsage),
                        caption: "total load",
                        color: Sensor.loadColor(snapshot.cpu.totalUsage)
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text(monitor.machine.chipName).font(.headline)
                        Text(monitor.machine.coreSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        BarRow(label: "User", value: snapshot.cpu.userUsage, tint: .blue)
                        BarRow(label: "System", value: snapshot.cpu.systemUsage, tint: .orange)
                        BarRow(label: "Idle", value: snapshot.cpu.idle, tint: .gray)
                    }
                }
                HistoryChart(history: monitor.history.cpuUsage, tint: .blue, maximum: 100)
            }

            Card("Per-core load", systemImage: "square.grid.3x3", tint: .blue) {
                let cores = orderedCores
                if cores.isEmpty {
                    Text("Collecting…").font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 6) {
                        ForEach(cores) { core in
                            BarRow(
                                label: core.label,
                                value: core.load,
                                tint: Sensor.loadColor(core.load),
                                labelWidth: 92
                            )
                        }
                    }
                }
            }

            Card("CPU temperatures", systemImage: "thermometer.medium", tint: .orange) {
                let sensors = snapshot.temperatures(in: .cpu) + snapshot.temperatures(in: .soc)
                if sensors.isEmpty {
                    EmptyStateView(
                        title: "No CPU thermal sensors",
                        message: "Apple silicon exposes die temperatures through IOHIDEventSystem; Intel Macs through the SMC. Neither returned CPU readings on this machine."
                    )
                } else {
                    if let peak = snapshot.cpuTemperaturePeak {
                        HistoryChart(
                            history: monitor.history.cpuTemperature,
                            tint: Sensor.temperatureColor(peak),
                            maximum: 110,
                            valueFormatter: { String(format: "%.0f°", $0) }
                        )
                    }
                    ForEach(sensors.sorted { $0.value > $1.value }) { sensor in
                        SensorRow(sensor: sensor, unit: unit)
                    }
                }
            }

            Card("System load", systemImage: "speedometer", tint: .green) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    MetricTile(title: "Load 1 min",
                               value: String(format: "%.2f", snapshot.cpu.loadAverage.0),
                               systemImage: "gauge.with.dots.needle.33percent", tint: .blue)
                    MetricTile(title: "Load 5 min",
                               value: String(format: "%.2f", snapshot.cpu.loadAverage.1),
                               systemImage: "gauge.with.dots.needle.50percent", tint: .indigo)
                    MetricTile(title: "Load 15 min",
                               value: String(format: "%.2f", snapshot.cpu.loadAverage.2),
                               systemImage: "gauge.with.dots.needle.67percent", tint: .purple)
                    MetricTile(title: "Processes", value: "\(snapshot.cpu.processCount)",
                               systemImage: "list.bullet.rectangle", tint: .teal)
                    MetricTile(title: "Uptime", value: Format.duration(snapshot.cpu.uptime),
                               systemImage: "clock", tint: .green)
                    MetricTile(title: "Thermal pressure", value: snapshot.power.thermalPressure,
                               systemImage: "thermometer.sun", tint: .orange)
                }
            }
        }
        .padding(16)
    }

    private struct LabelledCore: Identifiable {
        let id: Int
        let label: String
        let load: Double
    }

    /// `host_processor_info` lists the efficiency cluster first on Apple silicon; the list reads
    /// better the other way round, so performance cores are shown before efficiency cores.
    private var orderedCores: [LabelledCore] {
        let machine = monitor.machine
        let cores = snapshot.cpu.cores

        guard machine.isAppleSilicon,
              machine.efficiencyCores > 0,
              machine.performanceCores > 0,
              cores.count > machine.efficiencyCores else {
            return cores.map { LabelledCore(id: $0.id, label: "Core \($0.id)", load: $0.total) }
        }

        let efficiency = cores.prefix(machine.efficiencyCores).enumerated().map {
            LabelledCore(id: $0.element.id, label: "E-core \($0.offset)", load: $0.element.total)
        }
        let performance = cores.dropFirst(machine.efficiencyCores).enumerated().map {
            LabelledCore(id: $0.element.id, label: "P-core \($0.offset)", load: $0.element.total)
        }
        return performance + efficiency
    }
}
