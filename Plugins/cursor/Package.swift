// swift-tools-version: 6.0
import PackageDescription

/// The Cursor provider, as its own package.
let package = Package(
    name: "QuotaPluginCursor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota-provider-cursor", targets: ["QuotaPluginCursor"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPluginCursor",
            dependencies: [
                .product(name: "PluginKit", package: "Quota"),
            ]
        ),
    ]
)
