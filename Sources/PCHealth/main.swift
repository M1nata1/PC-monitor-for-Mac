import Foundation

// `--dump` / `--json` give a headless one-shot reading; otherwise launch the SwiftUI app.
let arguments = CommandLine.arguments
if arguments.contains("--bench") {
    SensorDump.bench()
    exit(EXIT_SUCCESS)
}

// Renders the tabs to PNGs for the README (see `make screenshots`).
if let index = arguments.firstIndex(of: "--screenshots") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "docs/screenshots"
    let width = arguments.firstIndex(of: "--width")
        .flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil }
    MainActor.assumeIsolated {
        width.map { ScreenshotRenderer.run(directory: directory, width: $0) }
            ?? ScreenshotRenderer.run(directory: directory)
    }
    exit(EXIT_SUCCESS)
}

if arguments.contains("--dump") || arguments.contains("--json") {
    SensorDump.run(json: arguments.contains("--json"))
    exit(EXIT_SUCCESS)
}

PCHealthApp.main()
