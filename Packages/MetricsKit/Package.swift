// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetricsKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // UI'dan bağımsız çekirdek: provider'lar, scheduler, store, engine.
        .library(name: "MetricsKit", targets: ["MetricsKit"]),
        // Xcode'a girmeden gerçek metrikleri terminalde görmek için demo aracı.
        .executable(name: "mectrics-cli", targets: ["MectricsCLI"])
    ],
    targets: [
        .target(
            name: "MetricsKit",
            swiftSettings: [
                // MVP boyunca Swift 5 dil modu: C tabanlı Mach/IOKit provider'larında
                // strict-concurrency sürtünmesini azaltır. İleride .v6'ya taşınacak.
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
