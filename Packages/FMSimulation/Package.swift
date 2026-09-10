// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FMSimulation",
    products: [
        .library(name: "FMSimulation", targets: ["FMSimulation"]),
        .library(name: "FMSimulationScenarios", targets: ["FMSimulationScenarios"]),
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
        // The rules-conformance scenarios, as scripted games a tool can link:
        // `gamelog --scenario <name>` walks one through the printer a seeded game goes
        // through. A plain FM* library — no Testing, no Foundation — because the
        // assertions over a scenario belong to the test target and a tool must not pull a
        // test framework in behind them.
        .target(
            name: "FMSimulationScenarios",
            dependencies: [
                "FMSimulation",
                .product(name: "FMCore", package: "FMCore"),
                .product(name: "FMGeneration", package: "FMGeneration"),
                .product(name: "FMRandom", package: "FMRandom"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FMSimulationTests",
            dependencies: [
                "FMSimulation",
                "FMSimulationScenarios",
                .product(name: "FMGeneration", package: "FMGeneration"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
