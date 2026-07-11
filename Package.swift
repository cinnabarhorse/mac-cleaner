// swift-tools-version: 6.1

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
        .target(
            name: "MacCleanerFeatures",
            dependencies: ["MacCleanerCore"]
        ),
        .executableTarget(
            name: "MacCleanerApp",
            dependencies: ["MacCleanerCore", "MacCleanerFeatures"]
        ),
        .testTarget(
            name: "MacCleanerCoreTests",
            dependencies: ["MacCleanerCore"]
        ),
        .testTarget(
            name: "MacCleanerFeaturesTests",
            dependencies: ["MacCleanerFeatures", "MacCleanerCore"]
        ),
        .testTarget(
            name: "MacCleanerPackagedAppE2ETests",
            dependencies: ["MacCleanerCore", "MacCleanerFeatures"]
        )
    ]
)
