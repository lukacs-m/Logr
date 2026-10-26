// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// tvOS and watchOS SDKs ship FoundationModels without the on-device system language model.
let systemModel: SwiftSetting = .define("LOGR_SYSTEM_MODEL",
                                        .when(platforms: [.iOS, .macOS, .macCatalyst, .visionOS]))

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
                 targets: ["LogrUI"]),
        .library(name: "LogrTesting",
                 targets: ["LogrTesting"]),
        .library(name: "LogrSwiftLog",
                 targets: ["LogrSwiftLog"]),
        .library(name: "LogrNetwork",
                 targets: ["LogrNetwork"])
    ],
    dependencies: [
           .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.61.0"),
           .package(url: "https://github.com/apple/swift-collections.git", .upToNextMajor(from: "1.5.1")),
           .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0"),
           .package(url: "https://github.com/apple/swift-log", from: "1.16.0")
    ],
    targets: [
        .target(
            name: "Logr",
            dependencies: [
                .product(name: "Collections", package: "swift-collections")
            ],
            swiftSettings: [
              .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
              .enableUpcomingFeature("InferIsolatedConformances"),
              .enableUpcomingFeature("ExistentialAny"),
              .enableUpcomingFeature("ImmutableWeakCaptures"),
              systemModel
            ]
        ),
        .target(
            name: "LogrUI",
            dependencies: ["Logr", "LogrNetwork"],
            swiftSettings: [
              .defaultIsolation(MainActor.self),
              .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
              .enableUpcomingFeature("InferIsolatedConformances")
            ]
        ),
        .target(
            name: "LogrTesting",
            dependencies: ["Logr"],
            swiftSettings: [
              .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
              .enableUpcomingFeature("InferIsolatedConformances"),
              .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "LogrSwiftLog",
            dependencies: [
                "Logr",
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
              .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
              .enableUpcomingFeature("InferIsolatedConformances"),
              .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "LogrNetwork",
            dependencies: ["Logr"],
            swiftSettings: [
              .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
              .enableUpcomingFeature("InferIsolatedConformances"),
              .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "LogrTests",
            dependencies: ["Logr", "LogrUI", "LogrTesting", "LogrSwiftLog", "LogrNetwork",
                           .product(name: "Logging", package: "swift-log")],
            resources: [.copy("Fixtures")],
            swiftSettings: [systemModel]
        ),
    ],
    swiftLanguageModes: [.v6]
)
