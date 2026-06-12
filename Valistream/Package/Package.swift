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
    ],
    targets: [
        .target(
            name: "ValistreamCore"
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
