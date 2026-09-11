// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VideoRenderingKit",
    platforms: [.tvOS(.v26), .macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "VideoRenderingKit", targets: ["VideoRenderingKit"])
    ],
    targets: [
        .target(name: "VideoRenderingKit"),
        .testTarget(name: "VideoRenderingKitTests", dependencies: ["VideoRenderingKit"])
    ]
)
