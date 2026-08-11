import SwiftUI
import AppKit

struct PCHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = SystemMonitor()
    @AppStorage("temperatureUnit") private var unitRaw = TemperatureUnit.celsius.rawValue

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }

    var body: some Scene {
        Window("PC Health", id: "main") {
            ContentView(monitor: monitor)
                .task { monitor.start() }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh now") { monitor.refreshOnce() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(monitor.isRunning ? "Pause sampling" : "Resume sampling") { monitor.toggle() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            // The menu bar title tracks the hottest of CPU/GPU, falling back to CPU load.
            if let temperature = monitor.snapshot.cpuTemperature ?? monitor.snapshot.gpuTemperature {
                Text("\(unit.format(temperature, decimals: 0))")
            } else {
                Text(Format.percent(monitor.snapshot.cpu.totalUsage))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Needed when the binary is launched straight from SwiftPM's build directory
        // rather than from a bundled .app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar after the window is closed.
        false
    }
}
