// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "simharness",
    dependencies: [
        .package(path: "../../Packages/FMCore"),
        .package(path: "../../Packages/FMGeneration"),
        .package(path: "../../Packages/FMRandom"),
        .package(path: "../../Packages/FMSimulation"),
    ],
    targets: [
        .executableTarget(
            name: "simharness",
            dependencies: [
                .product(name: "FMCore", package: "FMCore"),
                .product(name: "FMGeneration", package: "FMGeneration"),
                .product(name: "FMRandom", package: "FMRandom"),
                .product(name: "FMSimulation", package: "FMSimulation"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
