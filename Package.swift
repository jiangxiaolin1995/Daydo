// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DaydoCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DaydoCore", targets: ["DaydoCore"])],
    targets: [
        .target(name: "DaydoCore"),
        .testTarget(name: "DaydoCoreTests", dependencies: ["DaydoCore"])
    ],
    swiftLanguageModes: [.v6]
)
