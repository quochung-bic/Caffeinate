// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CaffeinateKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CaffeinateKit", targets: ["CaffeinateKit"])
    ],
    targets: [
        .target(name: "CaffeinateKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "CaffeinateKitTests",
            dependencies: ["CaffeinateKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
