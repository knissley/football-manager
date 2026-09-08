// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FMGeneration",
    products: [
        .library(name: "FMGeneration", targets: ["FMGeneration"])
    ],
    dependencies: [
        .package(path: "../FMCore"),
        .package(path: "../FMRandom"),
    ],
    targets: [
        .target(
            name: "FMGeneration",
            dependencies: [
                .product(name: "FMCore", package: "FMCore"),
                .product(name: "FMRandom", package: "FMRandom"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FMGenerationTests",
            dependencies: ["FMGeneration"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
