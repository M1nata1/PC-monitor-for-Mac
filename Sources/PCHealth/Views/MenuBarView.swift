import SwiftUI

/// Compact readout shown when the menu bar item is clicked.
struct MenuBarView: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("temperatureUnit") private var unitRaw = TemperatureUnit.celsius.rawValue
    @Environment(\.openWindow) private var openWindow

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }
    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monitor.machine.chipName)
                .font(.headline)

            row("CPU load", Format.percent(snapshot.cpu.totalUsage),
                Sensor.loadColor(snapshot.cpu.totalUsage), "cpu")
            if let temperature = snapshot.cpuTemperature {
                row("CPU temp", unit.format(temperature),
                    Sensor.temperatureColor(temperature), "thermometer.medium")
            }
            row("GPU load", Format.percent(snapshot.gpuUtilization),
                Sensor.loadColor(snapshot.gpuUtilization), "cpu.fill")
            if let temperature = snapshot.gpuTemperature {
                row("GPU temp", unit.format(temperature),
                    Sensor.temperatureColor(temperature), "thermometer.high")
            }
            row("Memory", Format.percent(snapshot.memory.usedPercent),
                Sensor.loadColor(snapshot.memory.usedPercent), "memorychip")
            if let fan = snapshot.power.fans.first {
                row("Fan", String(format: "%.0f RPM", fan.current), .cyan, "fan")
            }
            if let watts = snapshot.power.systemPowerWatts {
                row("Power", Format.watts(watts), .yellow, "bolt.fill")
            }
            if snapshot.power.battery.isPresent {
                row("Battery", Format.percent(snapshot.power.battery.charge),
                    snapshot.power.battery.charge < 20 ? .red : .green, "battery.75")
            }
            row("Network", "↓ \(Format.rate(snapshot.network.totalDownload))", .blue, "arrow.down.circle")

            Divider()

            HStack {
                Button("Open window") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 260)
    }

    private func row(_ title: String, _ value: String, _ color: Color, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(title)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
