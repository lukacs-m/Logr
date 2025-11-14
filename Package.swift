// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Logr",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "Logr",
            targets: ["Logr"]
        ),
        .library(name: "LogrUI",
                 targets: ["LogrUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", .upToNextMajor(from: "4.2.2")),
        .package(url: "https://github.com/pointfreeco/sqlite-data", .upToNextMajor(from: "1.3.0")),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.58.6"),
    ],
    targets: [
        .target(
            name: "Logr",
            dependencies: [
                .product(name: "KeychainAccess", package: "KeychainAccess"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            swiftSettings: [
              .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
              .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .target(
            name: "LogrUI",
            dependencies: ["Logr"],
            swiftSettings: [
              .defaultIsolation(MainActor.self),
              .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
              .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .testTarget(
            name: "LogrTests",
            dependencies: ["Logr"]
        ),
    ]
)
