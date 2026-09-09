// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FMSimulation",
    products: [
        .library(name: "FMSimulation", targets: ["FMSimulation"])
    ],
    dependencies: [
        .package(path: "../FMCore"),
        .package(path: "../FMGeneration"),
        .package(path: "../FMRandom"),
    ],
    targets: [
        .target(
            name: "FMSimulation",
            dependencies: [
                .product(name: "FMCore", package: "FMCore"),
                .product(name: "FMRandom", package: "FMRandom"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FMSimulationTests",
            dependencies: [
                "FMSimulation",
                .product(name: "FMGeneration", package: "FMGeneration"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
