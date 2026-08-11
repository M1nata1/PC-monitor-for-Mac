import SwiftUI

struct GPUView: View {
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
            if snapshot.gpus.isEmpty {
                Card {
                    EmptyStateView(
                        title: "No GPU statistics",
                        message: "No IOAccelerator / IOGPU service published a PerformanceStatistics dictionary.",
                        systemImage: "cpu.fill"
                    )
                }
            }

            ForEach(Array(snapshot.gpus.enumerated()), id: \.offset) { index, gpu in
                Card(gpu.name, systemImage: "cpu.fill", tint: .purple) {
                    HStack(spacing: 16) {
                        RingGauge(
                            value: gpu.deviceUtilization / 100,
                            label: Format.percent(gpu.deviceUtilization),
                            caption: "device",
                            color: Sensor.loadColor(gpu.deviceUtilization)
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            if let cores = gpu.coreCount {
                                Text("\(cores) GPU cores")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let renderer = gpu.rendererUtilization {
                                BarRow(label: "Renderer", value: renderer, tint: .purple)
                            }
                            if let tiler = gpu.tilerUtilization {
                                BarRow(label: "Tiler", value: tiler, tint: .pink)
                            }
                            if let used = gpu.usedMemory {
                                MetricTile(title: "VRAM in use", value: Format.bytes(used),
                                           detail: gpu.allocatedMemory.map { "allocated \(Format.bytes($0))" },
                                           systemImage: "memorychip", tint: .purple)
                            }
                        }
                    }

                    if index == 0 {
                        HistoryChart(history: monitor.history.gpuUsage, tint: .purple, maximum: 100)
                    }

                    if let recovery = gpu.recoveryCount, recovery > 0 {
                        Text("GPU resets since boot: \(recovery)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Card("GPU temperatures", systemImage: "thermometer.medium", tint: .orange) {
                let sensors = snapshot.temperatures(in: .gpu)
                if sensors.isEmpty {
                    EmptyStateView(
                        title: "No GPU thermal sensors",
                        message: "This machine does not publish a GPU die temperature."
                    )
                } else {
                    if let hottest = sensors.map(\.value).max() {
                        HistoryChart(
                            history: monitor.history.gpuTemperature,
                            tint: Sensor.temperatureColor(hottest),
                            maximum: 110,
                            valueFormatter: { String(format: "%.0f°", $0) }
                        )
                    }
                    ForEach(sensors.sorted { $0.value > $1.value }) { sensor in
                        SensorRow(sensor: sensor, unit: unit)
                    }
                }
            }
        }
        .padding(16)
    }
}
