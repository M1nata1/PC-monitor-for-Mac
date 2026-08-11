import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SensorsView: View {
    @ObservedObject var monitor: SystemMonitor
    let unit: TemperatureUnit

    @State private var query = ""
    @State private var kindFilter: SensorKind?

    private var sensors: [Sensor] {
        var result = monitor.snapshot.sensors
        if let kindFilter {
            result = result.filter { $0.kind == kindFilter }
        }
        if !query.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.key?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return result
    }

    private var grouped: [(group: SensorGroup, sensors: [Sensor])] {
        SensorGroup.allCases.compactMap { group in
            let matching = sensors.filter { $0.group == group }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return matching.isEmpty ? nil : (group, matching)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if sensors.isEmpty {
                EmptyStateView(
                    title: "No sensors match",
                    message: monitor.snapshot.sensors.isEmpty
                        ? "Nothing was returned by IOHIDEventSystem or the SMC yet. Give it a second, or check that the app is not sandboxed."
                        : "Try a different search term or filter."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView { list }
            }
        }
    }

    /// Split out of `body` so the screenshot renderer can draw the list without a scroll view —
    /// `ImageRenderer` renders a `ScrollView` as blank.
    @ViewBuilder
    var list: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(grouped, id: \.group) { section in
                Card(section.group.rawValue, systemImage: section.group.symbol,
                     tint: section.group.color,
                     accessory: AnyView(
                        Text("\(section.sensors.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                     )) {
                    ForEach(section.sensors) { sensor in
                        SensorRow(sensor: sensor, unit: unit)
                        if sensor.id != section.sensors.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter by name or SMC key", text: $query)
                .textFieldStyle(.plain)

            Picker("", selection: $kindFilter) {
                Text("All").tag(SensorKind?.none)
                Text("Temperature").tag(SensorKind?.some(.temperature))
                Text("Fan").tag(SensorKind?.some(.fan))
                Text("Power").tag(SensorKind?.some(.power))
                Text("Voltage").tag(SensorKind?.some(.voltage))
                Text("Current").tag(SensorKind?.some(.current))
            }
            .labelsHidden()
            .frame(width: 140)

            Text("\(sensors.count) sensors")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .help("Save the current readings as a CSV file")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "sensors-\(Int(Date().timeIntervalSince1970)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["group,name,key,source,kind,value,unit"]
        for sensor in sensors {
            let fields = [
                sensor.group.rawValue,
                sensor.name.replacingOccurrences(of: ",", with: " "),
                sensor.key ?? "",
                sensor.source.label,
                sensor.kind.rawValue,
                String(format: "%.3f", sensor.value),
                sensor.kind.unit
            ]
            lines.append(fields.joined(separator: ","))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
