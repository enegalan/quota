// swift-tools-version: 6.0
import PackageDescription

/// The Antigravity provider, as its own package.
let package = Package(
    name: "QuotaPluginAntigravity",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota-provider-antigravity", targets: ["QuotaPluginAntigravity"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPluginAntigravity",
            dependencies: [
                .product(name: "PluginKit", package: "Quota"),
                .product(name: "ProviderSupport", package: "Quota"),
            ]
        ),
        .testTarget(
            name: "AntigravityProviderTests",
            dependencies: [
                "QuotaPluginAntigravity",
                .product(name: "PluginKit", package: "Quota"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
