// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FMRandom",
    products: [
        .library(name: "FMRandom", targets: ["FMRandom"])
    ],
    targets: [
        .target(
            name: "FMRandom",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FMRandomTests",
            dependencies: ["FMRandom"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
