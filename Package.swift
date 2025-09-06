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
    ],
    targets: [
        .target(
            name: "Logr"
        ),
        .testTarget(
            name: "LogrTests",
            dependencies: ["Logr"]
        ),
    ]
)
