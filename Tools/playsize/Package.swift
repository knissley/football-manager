// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "playsize",
    dependencies: [
        .package(path: "../../Packages/FMCore"),
        .package(path: "../../Packages/FMGeneration"),
    ],
    targets: [
        .executableTarget(
            name: "playsize",
            dependencies: [
                .product(name: "FMCore", package: "FMCore"),
                .product(name: "FMGeneration", package: "FMGeneration"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
