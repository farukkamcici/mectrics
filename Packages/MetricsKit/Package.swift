// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetricsKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // UI-independent core: providers, scheduler, store, and engine.
        .library(name: "MetricsKit", targets: ["MetricsKit"]),
        // Demo tool for viewing live metrics without opening Xcode.
        .executable(name: "mectrics-cli", targets: ["MectricsCLI"])
    ],
    targets: [
        // The whole package builds in the Swift 6 language mode: providers wrap C-based
        // Mach/IOKit state in `@unchecked Sendable` types that own their own queue or
        // lock, so strict concurrency checks the boundaries we actually cross.
        .target(name: "MetricsKit"),
        .executableTarget(
            name: "MectricsCLI",
            dependencies: ["MetricsKit"]
        ),
        .testTarget(
            name: "MetricsKitTests",
            dependencies: ["MetricsKit"]
        )
    ]
)
