// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppCore",
            targets: ["AppCore"]
        )
    ],
    dependencies: [
        .package(path: "../HermesKit"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.2")
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: [
                .product(name: "HermesKit", package: "HermesKit"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ]
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"]
        )
    ]
)
