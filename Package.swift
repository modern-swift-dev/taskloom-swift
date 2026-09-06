// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TaskLoom",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "TaskLoom", targets: ["TaskLoom"]),
        .library(name: "TaskLoomTesting", targets: ["TaskLoomTesting"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.1"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.4"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.4"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "1.5.0")
    ],
    targets: [
        .target(
            name: "TaskLoom",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        ),
        .target(name: "TaskLoomTesting", dependencies: ["TaskLoom"]),
        .testTarget(name: "TaskLoomTestingTests", dependencies: ["TaskLoomTesting", "TaskLoom"]),
        .testTarget(
            name: "TaskLoomTests",
            dependencies: ["TaskLoom"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        )
    ],
    swiftLanguageModes: [.v6]
)
