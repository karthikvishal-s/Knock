// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "KnockKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "KnockKit", targets: ["KnockKit"]),
    ],
    targets: [
        .target(name: "KnockKit"),
        .testTarget(name: "KnockKitTests", dependencies: ["KnockKit"]),
    ]
)
