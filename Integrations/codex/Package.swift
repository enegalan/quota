// swift-tools-version: 6.0
import PackageDescription

/// The Codex provider, as its own package.
let package = Package(
    name: "QuotaPluginCodex",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota-provider-codex", targets: ["QuotaPluginCodex"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPluginCodex",
            dependencies: [
                .product(name: "PluginKit", package: "Quota"),
                .product(name: "ProviderSupport", package: "Quota"),
            ]
        ),
        .testTarget(
            name: "CodexProviderTests",
            dependencies: [
                "QuotaPluginCodex",
                .product(name: "PluginKit", package: "Quota"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
