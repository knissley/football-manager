// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "playsize",
    dependencies: [.package(path: "../../Packages/FMCore")],
    targets: [
        .executableTarget(
            name: "playsize",
            dependencies: [.product(name: "FMCore", package: "FMCore")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
