// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FMCore",
    products: [
        .library(name: "FMCore", targets: ["FMCore"])
    ],
    targets: [
        .target(
            name: "FMCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FMCoreTests",
            dependencies: ["FMCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
