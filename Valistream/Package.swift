// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Valistream",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ValistreamCore",
            targets: ["ValistreamCore"]
        ),
        .executable(
            name: "valistream",
            targets: ["valistream"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "ValistreamCore"
        ),
        .executableTarget(
            name: "valistream",
            dependencies: [
                "ValistreamCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ValistreamCoreTests",
            dependencies: ["ValistreamCore"]
        ),
        .testTarget(
            name: "ValistreamIntegrationTests",
            dependencies: ["ValistreamCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
