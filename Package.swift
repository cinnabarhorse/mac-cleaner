// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacCleaner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacCleaner", targets: ["MacCleanerApp"]),
        .library(name: "MacCleanerCore", targets: ["MacCleanerCore"])
    ],
    targets: [
        .target(name: "MacCleanerCore"),
        .executableTarget(
            name: "MacCleanerApp",
            dependencies: ["MacCleanerCore"]
        ),
        .testTarget(
            name: "MacCleanerCoreTests",
            dependencies: ["MacCleanerCore"]
        )
    ]
)
