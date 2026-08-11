import SwiftUI

struct MemoryView: View {
    @ObservedObject var monitor: SystemMonitor

    private var memory: MemoryStats { monitor.snapshot.memory }

    var body: some View {
        ScrollView { content }
    }

    /// Split out of `body` so the screenshot renderer can draw the page without a
    /// scroll view — `ImageRenderer` renders a `ScrollView` as blank.
    @ViewBuilder
    var content: some View {
        VStack(spacing: 14) {
            Card("Physical memory", systemImage: "memorychip", tint: .teal) {
                HStack(spacing: 16) {
                    RingGauge(
                        value: memory.usedPercent / 100,
                        label: Format.percent(memory.usedPercent),
                        caption: "used",
                        color: Sensor.loadColor(memory.usedPercent)
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Format.bytes(memory.used)) of \(Format.bytes(memory.total)) used")
                            .font(.headline)
                        Text("Pressure \(Format.percent(memory.pressurePercent))")
                            .font(.caption)
                            .foregroundStyle(Sensor.loadColor(memory.pressurePercent))
                        BarRow(label: "App", value: percent(memory.app),
                               trailing: Format.bytes(memory.app), tint: .teal)
                        BarRow(label: "Wired", value: percent(memory.wired),
                               trailing: Format.bytes(memory.wired), tint: .orange)
                        BarRow(label: "Compressed", value: percent(memory.compressed),
                               trailing: Format.bytes(memory.compressed), tint: .pink)
                        BarRow(label: "Cached", value: percent(memory.cached),
                               trailing: Format.bytes(memory.cached), tint: .gray)
                        BarRow(label: "Free", value: percent(memory.free),
                               trailing: Format.bytes(memory.free), tint: .green)
                    }
                }
                HistoryChart(history: monitor.history.memoryUsed, tint: .teal, maximum: 100)
            }

            Card("Swap", systemImage: "arrow.left.arrow.right.square", tint: .red) {
                if memory.swapTotal == 0 {
                    Text("No swap in use").font(.caption).foregroundStyle(.secondary)
                } else {
                    BarRow(
                        label: "Swap",
                        value: Double(memory.swapUsed) / Double(max(memory.swapTotal, 1)) * 100,
                        trailing: "\(Format.bytes(memory.swapUsed)) / \(Format.bytes(memory.swapTotal))",
                        tint: .red
                    )
                }
            }
        }
        .padding(16)
    }

    private func percent(_ bytes: UInt64) -> Double {
        memory.total == 0 ? 0 : Double(bytes) / Double(memory.total) * 100
    }
}

struct StorageView: View {
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
            Card("Throughput", systemImage: "internaldrive", tint: .green) {
                HStack(spacing: 10) {
                    MetricTile(title: "Read", value: Format.rate(snapshot.diskIO.readBytesPerSecond),
                               detail: "total \(Format.bytes(snapshot.diskIO.totalRead))",
                               systemImage: "arrow.down.doc", tint: .green)
                    MetricTile(title: "Write", value: Format.rate(snapshot.diskIO.writeBytesPerSecond),
                               detail: "total \(Format.bytes(snapshot.diskIO.totalWritten))",
                               systemImage: "arrow.up.doc", tint: .mint)
                }
                HistoryChart(history: monitor.history.diskRead, tint: .green,
                             maximum: nil, valueFormatter: { Format.rate($0) })
                HistoryChart(history: monitor.history.diskWrite, tint: .mint,
                             maximum: nil, valueFormatter: { Format.rate($0) })
            }

            Card("Volumes", systemImage: "externaldrive", tint: .mint) {
                if snapshot.volumes.isEmpty {
                    Text("Collecting…").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.volumes) { volume in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(volume.name, systemImage: volume.isRemovable ? "externaldrive" : "internaldrive")
                                    .font(.callout)
                                Spacer()
                                Text("\(Format.bytes(volume.used)) / \(Format.bytes(volume.total))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            BarRow(label: volume.path, value: volume.usedPercent,
                                   tint: Sensor.loadColor(volume.usedPercent), labelWidth: 140)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            let sensors = snapshot.temperatures(in: .storage)
            if !sensors.isEmpty {
                Card("Drive temperatures", systemImage: "thermometer.medium", tint: .orange) {
                    ForEach(sensors.sorted { $0.value > $1.value }) { sensor in
                        SensorRow(sensor: sensor, unit: unit)
                    }
                }
            }
        }
        .padding(16)
    }
}

struct NetworkView: View {
    @ObservedObject var monitor: SystemMonitor

    private var network: NetworkStats { monitor.snapshot.network }

    var body: some View {
        ScrollView { content }
    }

    /// Split out of `body` so the screenshot renderer can draw the page without a
    /// scroll view — `ImageRenderer` renders a `ScrollView` as blank.
    @ViewBuilder
    var content: some View {
        VStack(spacing: 14) {
            Card("Traffic", systemImage: "network", tint: .blue) {
                HStack(spacing: 10) {
                    MetricTile(title: "Download", value: Format.rate(network.totalDownload),
                               detail: network.localAddress.map { "IP \($0)" },
                               systemImage: "arrow.down.circle", tint: .blue)
                    MetricTile(title: "Upload", value: Format.rate(network.totalUpload),
                               detail: network.primaryInterface.map { "primary \($0)" },
                               systemImage: "arrow.up.circle", tint: .indigo)
                }
                HistoryChart(history: monitor.history.networkDown, tint: .blue,
                             maximum: nil, valueFormatter: { Format.rate($0) })
                HistoryChart(history: monitor.history.networkUp, tint: .indigo,
                             maximum: nil, valueFormatter: { Format.rate($0) })
            }

            Card("Interfaces", systemImage: "cable.connector", tint: .indigo) {
                if network.interfaces.isEmpty {
                    Text("Collecting…").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(network.interfaces) { interface in
                        HStack {
                            Text(interface.name)
                                .font(.callout.monospaced())
                                .frame(width: 70, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("↓ \(Format.rate(interface.downloadBytesPerSecond))  ↑ \(Format.rate(interface.uploadBytesPerSecond))")
                                    .font(.caption.monospacedDigit())
                                Text("total ↓ \(Format.bytes(interface.totalDownload))  ↑ \(Format.bytes(interface.totalUpload))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .padding(16)
    }
}
