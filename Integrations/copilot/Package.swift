// swift-tools-version: 6.0
import PackageDescription

/// The GitHub Copilot provider, as its own package.
let package = Package(
    name: "QuotaPluginCopilot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota-provider-copilot", targets: ["QuotaPluginCopilot"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPluginCopilot",
            dependencies: [
                .product(name: "PluginKit", package: "Quota"),
                .product(name: "ProviderSupport", package: "Quota"),
            ]
        ),
        .testTarget(
            name: "CopilotProviderTests",
            dependencies: [
                "QuotaPluginCopilot",
                .product(name: "PluginKit", package: "Quota"),
                .product(name: "ProviderSupport", package: "Quota"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
