import SwiftUI
import AppKit

/// `PCHealth --screenshots <dir>` renders every tab offscreen with live readings and writes
/// PNGs for the README. Driven by `make screenshots`.
///
/// The pages are drawn through `ImageRenderer` rather than captured from the window: a
/// screen capture needs the Screen Recording permission, this does not. Note that
/// `ImageRenderer` draws a `ScrollView` as blank, which is why each view exposes its page
/// content separately from `body`.
@MainActor
enum ScreenshotRenderer {

    /// Enough samples to fill the chart buffer, spaced out so the traffic and load numbers
    /// are real rather than a burst of back-to-back reads.
    private static let warmupSamples = 120
    private static let warmupPause: TimeInterval = 0.1
    private nonisolated static let defaultWidth: CGFloat = 980

    static func run(directory: String, width: CGFloat = defaultWidth) {
        let monitor = SystemMonitor()
        let collector = SystemCollector()

        for sample in 0..<warmupSamples {
            monitor.apply(collector.collect(fullSensorScan: true))
            Thread.sleep(forTimeInterval: warmupPause)
            if sample % 20 == 0 {
                FileHandle.standardError.write(
                    "warming up \(sample)/\(warmupSamples)…\n".data(using: .utf8)!)
            }
        }

        let unit = TemperatureUnit.celsius
        // Pages whose natural height runs into the thousands of points get cropped; the CPU
        // page in particular lists every SoC sensor the machine has.
        let pages: [(name: String, view: AnyView, height: CGFloat?)] = [
            ("dashboard", AnyView(DashboardView(monitor: monitor, unit: unit).content), nil),
            ("cpu", AnyView(CPUView(monitor: monitor, unit: unit).content), 1080),
            ("gpu", AnyView(GPUView(monitor: monitor, unit: unit).content), 1080),
            ("memory", AnyView(MemoryView(monitor: monitor).content), nil),
            ("storage", AnyView(StorageView(monitor: monitor, unit: unit).content), nil),
            ("network", AnyView(NetworkView(monitor: monitor).content), nil),
            ("power", AnyView(PowerView(monitor: monitor, unit: unit).content), 1080),
            ("sensors", AnyView(SensorsView(monitor: monitor, unit: unit).list), 1080)
        ]

        let directoryURL = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        for page in pages {
            let composed = page.view
                .frame(width: width, height: page.height, alignment: .top)
                .clipped()
                .environment(\.colorScheme, .dark)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))

            let renderer = ImageRenderer(content: composed)
            // 1.5× keeps the text crisp on a Retina display without 1 MB PNGs in the repo.
            renderer.scale = 1.5

            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write("failed: \(page.name)\n".data(using: .utf8)!)
                continue
            }

            let url = directoryURL.appendingPathComponent("\(page.name).png")
            try? data.write(to: url)
            print("\(url.lastPathComponent)  \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        }
    }
}
