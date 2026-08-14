// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SmartMovieKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SmartMovieKit", targets: ["SmartMovieKit"])
    ],
    targets: [
        .target(
            name: "SmartMovieKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SmartMovieKitTests",
            dependencies: ["SmartMovieKit"],
            resources: [.process("Fixtures")]
        )
    ]
)
