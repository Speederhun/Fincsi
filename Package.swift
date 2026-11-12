// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FincsiKit",
    defaultLocalization: "hu",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FincsiKit", targets: ["FincsiKit"])
    ],
    targets: [
        .target(
            name: "FincsiKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FincsiKitTests",
            dependencies: ["FincsiKit"]
        )
    ]
)
