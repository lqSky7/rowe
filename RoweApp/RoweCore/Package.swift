// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RoweCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "RoweCore",
            targets: ["RoweCore"]
        )
    ],
    targets: [
        .target(
            name: "RoweCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "RoweCoreTests",
            dependencies: ["RoweCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
