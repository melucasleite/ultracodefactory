// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeFactoryKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CodeFactoryKit", targets: ["CodeFactoryKit"]),
    ],
    targets: [
        .target(name: "CodeFactoryKit"),
        .testTarget(name: "CodeFactoryKitTests", dependencies: ["CodeFactoryKit"]),
    ]
)
