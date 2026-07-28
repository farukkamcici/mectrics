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
        .target(
            name: "MetricsKit",
            swiftSettings: [
                // Keep Swift 5 language mode during the MVP to reduce strict-concurrency
                // friction in C-based Mach/IOKit providers. Migrate to Swift 6 later.
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "MectricsCLI",
            dependencies: ["MetricsKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MetricsKitTests",
            dependencies: ["MetricsKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
