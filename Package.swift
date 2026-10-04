// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Quota",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Quota", targets: ["App"]),
        .library(name: "PluginKit", targets: ["PluginKit"]),
    ],
    targets: [
        .target(
            name: "Core",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PluginKit",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Platform",
            dependencies: ["Core", "PluginKit"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "App",
            dependencies: ["Core", "PluginKit", "Platform"],
            resources: [
                .copy("Resources/quota.png"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "TestPlugin",
            dependencies: ["PluginKit"],
            path: "Tests/Fixtures/TestPlugin",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["App", "Core", "Platform"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PluginKitTests",
            dependencies: ["PluginKit"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PlatformTests",
            dependencies: ["Platform"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CursorProviderTests",
            dependencies: ["Core", "Platform", "PluginKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ]
)

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]
