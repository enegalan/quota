// swift-tools-version: 6.0
import PackageDescription

/// The JetBrains AI Assistant provider, as its own package.
let package = Package(
    name: "QuotaPluginJetBrains",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota-provider-jetbrains", targets: ["QuotaPluginJetBrains"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPluginJetBrains",
            dependencies: [
                .product(name: "PluginKit", package: "Quota"),
                .product(name: "ProviderSupport", package: "Quota"),
            ]
        ),
        .testTarget(
            name: "JetBrainsProviderTests",
            dependencies: [
                "QuotaPluginJetBrains",
                .product(name: "PluginKit", package: "Quota"),
                .product(name: "ProviderSupport", package: "Quota"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
