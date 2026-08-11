import SwiftUI

struct PowerView: View {
    @ObservedObject var monitor: SystemMonitor
    let unit: TemperatureUnit

    private var power: PowerStats { monitor.snapshot.power }

    var body: some View {
        ScrollView { content }
    }

    /// Split out of `body` so the screenshot renderer can draw the page without a
    /// scroll view — `ImageRenderer` renders a `ScrollView` as blank.
    @ViewBuilder
    var content: some View {
        VStack(spacing: 14) {
            if let rail = power.systemPower {
                Card("Power draw — \(rail.name)", systemImage: "bolt.fill", tint: .yellow) {
                    Text(Format.watts(rail.value))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    HistoryChart(history: monitor.history.systemPower, tint: .yellow,
                                 maximum: nil, valueFormatter: { String(format: "%.0fW", $0) })
                }
            }

            Card("Cooling", systemImage: "fan", tint: .cyan) {
                if power.fans.isEmpty {
                    EmptyStateView(
                        title: "No fans reported",
                        message: "Fanless Mac, or the SMC does not expose fan keys on this model.",
                        systemImage: "fan.slash"
                    )
                } else {
                    ForEach(power.fans) { fan in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Fan \(fan.index + 1)", systemImage: "fan")
                                    .font(.callout)
                                Spacer()
                                Text(String(format: "%.0f RPM", fan.current))
                                    .font(.callout.monospacedDigit())
                            }
                            BarRow(
                                label: "speed",
                                value: fan.normalized * 100,
                                trailing: fanRange(fan),
                                tint: .cyan,
                                labelWidth: 52
                            )
                        }
                        .padding(.vertical, 4)
                    }
                    HistoryChart(history: monitor.history.fanSpeed, tint: .cyan,
                                 maximum: nil, valueFormatter: { String(format: "%.0f", $0) })
                }
            }

            Card("Battery", systemImage: "battery.100", tint: .green) {
                if power.battery.isPresent {
                    batteryDetails(power.battery)
                } else {
                    EmptyStateView(
                        title: "No battery",
                        message: "This Mac runs on AC power only.",
                        systemImage: "powerplug"
                    )
                }
            }

            if !power.rails.isEmpty {
                Card("Power rails (SMC)", systemImage: "bolt.horizontal", tint: .yellow) {
                    ForEach(power.rails) { sensor in
                        SensorRow(sensor: sensor, unit: unit)
                    }
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func batteryDetails(_ battery: BatteryStats) -> some View {
        HStack(spacing: 16) {
            RingGauge(
                value: battery.charge / 100,
                label: Format.percent(battery.charge),
                caption: battery.isCharging ? "charging" : (battery.isPluggedIn ? "on AC" : "on battery"),
                color: battery.charge < 20 ? .red : (battery.charge < 50 ? .yellow : .green)
            )
            // Uniform cells: `stretch` makes every tile as tall as the tallest in its row, so
            // the ones without a detail line do not float in the middle of the row.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 10, alignment: .top)],
                spacing: 10
            ) {
                if let health = battery.health {
                    MetricTile(title: "Health", value: Format.percent(health),
                               detail: capacityDetail(battery),
                               systemImage: "heart.text.square",
                               tint: health < 80 ? .orange : .green,
                               stretch: true)
                }
                if let cycles = battery.cycleCount {
                    MetricTile(title: "Cycles", value: "\(cycles)",
                               systemImage: "arrow.triangle.2.circlepath", tint: .blue,
                               stretch: true)
                }
                if let temperature = battery.temperature {
                    MetricTile(title: "Temperature", value: unit.format(temperature),
                               systemImage: "thermometer.medium",
                               tint: Sensor.temperatureColor(temperature),
                               stretch: true)
                }
                if let voltage = battery.voltage {
                    MetricTile(title: "Voltage", value: String(format: "%.2f V", voltage),
                               systemImage: "bolt.horizontal", tint: .yellow,
                               stretch: true)
                }
                if let amperage = battery.amperage {
                    MetricTile(title: "Current", value: String(format: "%.2f A", amperage),
                               detail: battery.powerWatts.map { Format.watts($0) },
                               systemImage: "waveform.path.ecg", tint: .purple,
                               stretch: true)
                }
                if let minutes = battery.timeToEmptyMinutes {
                    MetricTile(title: "Time remaining", value: Format.minutes(minutes),
                               systemImage: "hourglass", tint: .teal,
                               stretch: true)
                }
                if let minutes = battery.timeToFullMinutes {
                    MetricTile(title: "Time to full", value: Format.minutes(minutes),
                               systemImage: "hourglass.bottomhalf.filled", tint: .green,
                               stretch: true)
                }
            }
        }
    }

    private func capacityDetail(_ battery: BatteryStats) -> String? {
        guard let maximum = battery.maxCapacity, let design = battery.designCapacity else { return nil }
        return "\(maximum) / \(design) mAh"
    }

    private func fanRange(_ fan: FanStats) -> String {
        guard let minimum = fan.minimum, let maximum = fan.maximum else { return "" }
        return String(format: "%.0f–%.0f", minimum, maximum)
    }
}
