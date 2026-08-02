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
        // Read-only automation interface shipped inside Mectrics.app.
        .executable(name: "mectrics", targets: ["MectricsCLI"]),
        // Internal provider readout for development and hardware validation.
        .executable(name: "metricskit-demo", targets: ["MetricsKitDemo"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            exact: "1.8.2"
        )
    ],
    targets: [
        // The whole package builds in the Swift 6 language mode: providers wrap C-based
        // Mach/IOKit state in `@unchecked Sendable` types that own their own queue or
        // lock, so strict concurrency checks the boundaries we actually cross.
        .target(name: "MetricsKit"),
        .target(
            name: "MectricsCLICore",
            dependencies: [
                "MetricsKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "MectricsCLI",
            dependencies: ["MectricsCLICore"]
        ),
        .executableTarget(
            name: "MetricsKitDemo",
            dependencies: ["MetricsKit"]
        ),
        .testTarget(
            name: "MetricsKitTests",
            dependencies: ["MetricsKit"]
        ),
        .testTarget(
            name: "MectricsCLITests",
            dependencies: ["MectricsCLICore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
