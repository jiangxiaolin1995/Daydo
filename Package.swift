// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DaydoCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DaydoCore", targets: ["DaydoCore"]),
        .library(name: "DaydoDesktop", targets: ["DaydoDesktop"])
    ],
    targets: [
        .target(name: "DaydoCore"),
        .target(name: "DaydoDesktop"),
        .testTarget(name: "DaydoCoreTests", dependencies: ["DaydoCore"]),
        .testTarget(name: "DaydoDesktopTests", dependencies: ["DaydoDesktop"])
    ],
    swiftLanguageModes: [.v6]
)
