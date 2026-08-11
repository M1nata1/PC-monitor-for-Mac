import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    let unit: TemperatureUnit

    private var snapshot: SystemSnapshot { monitor.snapshot }

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView { content }
    }

    /// Split out of `body` so the screenshot renderer can draw the page without a
    /// scroll view — `ImageRenderer` renders a `ScrollView` as blank.
    @ViewBuilder
    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            gauges
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                cpuCard
                gpuCard
                memoryCard
                thermalCard
                powerCard
                trafficCard
            }
        }
        .padding(16)
    }

    // MARK: - Header

    private var header: some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.machine.chipName)
                        .font(.title3.weight(.semibold))
                    Text("\(monitor.machine.modelIdentifier) · \(monitor.machine.coreSummary) · \(Format.bytes(monitor.machine.physicalMemory)) RAM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("macOS \(monitor.machine.osVersion) · uptime \(Format.duration(snapshot.cpu.uptime)) · sensors via \(monitor.sensorSources)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Gauges

    private struct Gauge: Identifiable {
        let id: String
        let value: Double
        let label: String
        let caption: String
        let color: Color
    }

    /// Only the gauges the machine can actually fill; they share the row width equally.
    private var gaugeItems: [Gauge] {
        var items: [Gauge] = [
            Gauge(id: "cpu-load", value: snapshot.cpu.totalUsage / 100,
                  label: Format.percent(snapshot.cpu.totalUsage), caption: "CPU load",
                  color: Sensor.loadColor(snapshot.cpu.totalUsage))
        ]
        if let temperature = snapshot.cpuTemperature {
            items.append(Gauge(id: "cpu-temp", value: temperature / 110,
                               label: unit.format(temperature, decimals: 0), caption: "CPU temp",
                               color: Sensor.temperatureColor(temperature)))
        }
        items.append(Gauge(id: "gpu-load", value: snapshot.gpuUtilization / 100,
                           label: Format.percent(snapshot.gpuUtilization), caption: "GPU load",
                           color: Sensor.loadColor(snapshot.gpuUtilization)))
        if let temperature = snapshot.gpuTemperature {
            items.append(Gauge(id: "gpu-temp", value: temperature / 110,
                               label: unit.format(temperature, decimals: 0), caption: "GPU temp",
                               color: Sensor.temperatureColor(temperature)))
        }
        items.append(Gauge(id: "memory", value: snapshot.memory.usedPercent / 100,
                           label: Format.percent(snapshot.memory.usedPercent), caption: "Memory",
                           color: Sensor.loadColor(snapshot.memory.usedPercent)))
        if let rail = snapshot.power.systemPower {
            items.append(Gauge(id: "power", value: min(rail.value / 60, 1),
                               label: String(format: "%.0fW", rail.value), caption: "Power",
                               color: .yellow))
        }
        return items
    }

    private var gauges: some View {
        Card {
            // Wrapping layout rather than an HStack: in a narrow window the gauges move onto a
            // second row instead of being squeezed until they overlap.
            FlowLayout(spacing: 16, lineSpacing: 14) {
                ForEach(gaugeItems) { item in
                    RingGauge(value: item.value, label: item.label,
                              caption: item.caption, color: item.color)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Cards

    private var cpuCard: some View {
        Card("CPU", systemImage: "cpu", tint: .blue, stretch: true) {
            HistoryChart(history: monitor.history.cpuUsage, tint: .blue, maximum: 100)
            HStack {
                Label(Format.percent(snapshot.cpu.userUsage) + " user", systemImage: "person")
                Spacer()
                Label(Format.percent(snapshot.cpu.systemUsage) + " sys", systemImage: "gearshape")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(String(format: "Load avg %.2f · %.2f · %.2f · %d processes",
                        snapshot.cpu.loadAverage.0, snapshot.cpu.loadAverage.1,
                        snapshot.cpu.loadAverage.2, snapshot.cpu.processCount))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var gpuCard: some View {
        Card("GPU", systemImage: "cpu.fill", tint: .purple, stretch: true) {
            HistoryChart(history: monitor.history.gpuUsage, tint: .purple, maximum: 100)
            if let gpu = snapshot.gpus.first {
                Text(gpu.name + (gpu.coreCount.map { " · \($0) cores" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let used = gpu.usedMemory {
                    Text("VRAM in use \(Format.bytes(used))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("No accelerator reported statistics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var memoryCard: some View {
        Card("Memory", systemImage: "memorychip", tint: .teal, stretch: true) {
            HistoryChart(history: monitor.history.memoryUsed, tint: .teal, maximum: 100)
            BarRow(label: "App", value: percentOfRam(snapshot.memory.app),
                   trailing: Format.bytes(snapshot.memory.app), tint: .teal)
            BarRow(label: "Wired", value: percentOfRam(snapshot.memory.wired),
                   trailing: Format.bytes(snapshot.memory.wired), tint: .orange)
            BarRow(label: "Compressed", value: percentOfRam(snapshot.memory.compressed),
                   trailing: Format.bytes(snapshot.memory.compressed), tint: .pink)
            if snapshot.memory.swapUsed > 0 {
                Text("Swap \(Format.bytes(snapshot.memory.swapUsed)) of \(Format.bytes(snapshot.memory.swapTotal))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var thermalCard: some View {
        Card("Hottest sensors", systemImage: "thermometer.high", tint: .orange, stretch: true) {
            let hottest = snapshot.sensors
                .filter { $0.kind == .temperature }
                .sorted { $0.value > $1.value }
                .prefix(6)

            if hottest.isEmpty {
                EmptyStateView(
                    title: "No temperature sensors",
                    message: "This Mac did not expose thermal sensors through IOHIDEventSystem or the SMC.",
                    systemImage: "thermometer.slash"
                )
            } else {
                ForEach(Array(hottest)) { sensor in
                    SensorRow(sensor: sensor, unit: unit)
                }
            }
        }
    }

    private var powerCard: some View {
        Card("Power & cooling", systemImage: "bolt.circle", tint: .yellow, stretch: true) {
            if let rail = snapshot.power.systemPower {
                MetricTile(title: "Power draw", value: Format.watts(rail.value),
                           detail: rail.name, systemImage: "bolt.fill", tint: .yellow)
            }
            if snapshot.power.battery.isPresent {
                let battery = snapshot.power.battery
                MetricTile(
                    title: battery.isCharging ? "Battery (charging)" : "Battery",
                    value: Format.percent(battery.charge),
                    detail: batteryDetail(battery),
                    systemImage: battery.isPluggedIn ? "battery.100.bolt" : "battery.75",
                    tint: battery.charge < 20 ? .red : .green
                )
            }
            if snapshot.power.fans.isEmpty {
                MetricTile(title: "Fans", value: "Fanless / not reported",
                           systemImage: "fan.slash", tint: .secondary)
            } else {
                ForEach(snapshot.power.fans) { fan in
                    MetricTile(
                        title: "Fan \(fan.index + 1)",
                        value: String(format: "%.0f RPM", fan.current),
                        detail: fan.maximum.map { String(format: "max %.0f RPM", $0) },
                        systemImage: "fan",
                        tint: .cyan
                    )
                }
            }
        }
    }

    private var trafficCard: some View {
        Card("Network & disk", systemImage: "arrow.up.arrow.down", tint: .cyan, stretch: true) {
            MetricTile(title: "Download", value: Format.rate(snapshot.network.totalDownload),
                       detail: snapshot.network.primaryInterface.map { "via \($0)" },
                       systemImage: "arrow.down.circle", tint: .blue)
            MetricTile(title: "Upload", value: Format.rate(snapshot.network.totalUpload),
                       detail: snapshot.network.localAddress,
                       systemImage: "arrow.up.circle", tint: .indigo)
            MetricTile(title: "Disk read", value: Format.rate(snapshot.diskIO.readBytesPerSecond),
                       systemImage: "internaldrive", tint: .green)
            MetricTile(title: "Disk write", value: Format.rate(snapshot.diskIO.writeBytesPerSecond),
                       systemImage: "square.and.arrow.down", tint: .mint)
        }
    }

    // MARK: - Helpers

    private func percentOfRam(_ bytes: UInt64) -> Double {
        let total = snapshot.memory.total
        return total == 0 ? 0 : Double(bytes) / Double(total) * 100
    }

    private func batteryDetail(_ battery: BatteryStats) -> String? {
        var parts: [String] = []
        if let health = battery.health { parts.append(String(format: "health %.0f%%", health)) }
        if let cycles = battery.cycleCount { parts.append("\(cycles) cycles") }
        if let minutes = battery.timeToEmptyMinutes { parts.append("\(Format.minutes(minutes)) left") }
        if let minutes = battery.timeToFullMinutes { parts.append("\(Format.minutes(minutes)) to full") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
