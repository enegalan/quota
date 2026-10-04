// swift-tools-version: 6.0
import PackageDescription

/// The mock provider, as its own package.
///
/// A separate package on purpose, not a target in the application's.
let package = Package(
    name: "QuotaPluginMock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota-provider-mock", targets: ["QuotaPluginMock"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPluginMock",
            dependencies: [
                .product(name: "PluginKit", package: "Quota"),
            ]
        ),
    ]
)
