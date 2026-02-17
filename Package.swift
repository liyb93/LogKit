// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LogKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "LogKit",
            targets: ["LogKit"]
        )
    ],
    targets: [
        .target(
            name: "LogKit"
        ),
        .testTarget(
            name: "LogKitTests",
            dependencies: ["LogKit"]
        )
    ]
)
