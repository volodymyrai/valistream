// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Valistream",
    platforms: [
        .macOS("14")
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "valistream",
            targets: ["Valistream"]
        ),
        .library(
            name: "ValistreamCore",
            targets: ["ValistreamCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/onmyway133/Promptberry.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/onevcat/Rainbow.git", .upToNextMajor(from: "4.2.1")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.8.2")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Valistream",
            dependencies: [
                .target(name: "ValistreamCore"),
                .byName(name: "Promptberry"),
                .byName(name: "Rainbow"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "ValistreamTests",
            dependencies: [
                .target(name: "Valistream"),
                .target(name: "ValistreamCore")
            ]
        ),
        .target(
            name: "ValistreamCore"
        ),
        .testTarget(
            name: "ValistreamCoreTests",
            dependencies: [
                .target(name: "ValistreamCore")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
