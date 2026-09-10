// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gamelog",
    dependencies: [
        .package(path: "../../Packages/FMCore"),
        .package(path: "../../Packages/FMGeneration"),
        .package(path: "../../Packages/FMRandom"),
        .package(path: "../../Packages/FMSimulation"),
    ],
    targets: [
        .executableTarget(
            name: "gamelog",
            dependencies: [
                .product(name: "FMCore", package: "FMCore"),
                .product(name: "FMGeneration", package: "FMGeneration"),
                .product(name: "FMRandom", package: "FMRandom"),
                .product(name: "FMSimulation", package: "FMSimulation"),
                .product(name: "FMSimulationScenarios", package: "FMSimulation"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
