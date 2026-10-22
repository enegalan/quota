// swift-tools-version: 6.0
import PackageDescription

/// The Claude provider, as its own package.
let package = Package(
    name: "QuotaPluginClaude",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota-provider-claude", targets: ["QuotaPluginClaude"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPluginClaude",
            dependencies: [
                .product(name: "PluginKit", package: "Quota"),
                .product(name: "ProviderSupport", package: "Quota"),
            ]
        ),
        .testTarget(
            name: "ClaudeProviderTests",
            dependencies: [
                "QuotaPluginClaude",
                .product(name: "PluginKit", package: "Quota"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
