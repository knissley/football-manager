// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "worldgen",
    dependencies: [
        .package(path: "../../Packages/FMCore"),
        .package(path: "../../Packages/FMGeneration"),
        .package(path: "../../Packages/FMRandom"),
    ],
    targets: [
        .executableTarget(
            name: "worldgen",
            dependencies: [
                .product(name: "FMCore", package: "FMCore"),
                .product(name: "FMGeneration", package: "FMGeneration"),
                .product(name: "FMRandom", package: "FMRandom"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
