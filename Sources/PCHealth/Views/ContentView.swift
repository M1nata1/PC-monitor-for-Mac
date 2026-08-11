import SwiftUI

enum Section: String, CaseIterable, Identifiable, Hashable {
    case dashboard = "Dashboard"
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "Memory"
    case storage = "Storage"
    case network = "Network"
    case power = "Power & Fans"
    case sensors = "All sensors"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .power: return "bolt.circle"
        case .sensors: return "sensor.tag.radiowaves.forward"
        }
    }
}

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @AppStorage("temperatureUnit") private var unitRaw = TemperatureUnit.celsius.rawValue

    @State private var selection: Section? = .dashboard

    private var unit: TemperatureUnit {
        TemperatureUnit(rawValue: unitRaw) ?? .celsius
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.symbol)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 200)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            detail
                .navigationTitle((selection ?? .dashboard).rawValue)
                .toolbar { toolbarContent }
        }
        // Wide enough that the six dashboard gauges always fit on one line: six 96 pt rings
        // with 16 pt gaps need 656 pt, plus card and page padding (64 pt) and the widest the
        // sidebar can be dragged (200 pt), with a little slack for an always-visible scrollbar.
        .frame(minWidth: 950, minHeight: 560)
        // Polling every voltage and current rail is only worth it while they are on screen.
        .onAppear { monitor.fullSensorScan = selection == .sensors }
        .onChange(of: selection) { _, newValue in
            monitor.fullSensorScan = newValue == .sensors
            if newValue == .sensors { monitor.refreshOnce() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard: DashboardView(monitor: monitor, unit: unit)
        case .cpu: CPUView(monitor: monitor, unit: unit)
        case .gpu: GPUView(monitor: monitor, unit: unit)
        case .memory: MemoryView(monitor: monitor)
        case .storage: StorageView(monitor: monitor, unit: unit)
        case .network: NetworkView(monitor: monitor)
        case .sensors: SensorsView(monitor: monitor, unit: unit)
        case .power: PowerView(monitor: monitor, unit: unit)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(monitor.isRunning ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(monitor.isRunning
                     ? "Sampling every \(Int(monitor.refreshInterval))s"
                     : "Paused")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Unit", selection: $unitRaw) {
                ForEach(TemperatureUnit.allCases, id: \.rawValue) { unit in
                    Text(unit.rawValue).tag(unit.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .help("Temperature unit")

            Picker("Interval", selection: $monitor.refreshInterval) {
                Text("1s").tag(1.0)
                Text("2s").tag(2.0)
                Text("5s").tag(5.0)
                Text("10s").tag(10.0)
            }
            .frame(width: 80)
            .help("Refresh interval")

            Button {
                monitor.refreshOnce()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh now")

            Button {
                monitor.toggle()
            } label: {
                Image(systemName: monitor.isRunning ? "pause.fill" : "play.fill")
            }
            .help(monitor.isRunning ? "Pause sampling" : "Resume sampling")
        }
    }
}
