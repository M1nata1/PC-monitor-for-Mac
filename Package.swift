// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PCHealth",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PCHealth", targets: ["PCHealth"])
    ],
    targets: [
        .executableTarget(
            name: "PCHealth",
            path: "Sources/PCHealth",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts")
            ]
        )
    ]
)
