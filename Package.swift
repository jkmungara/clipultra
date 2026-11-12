// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "clipultra",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "clipultra", targets: ["clipultra"]),
    ],
    targets: [
        .target(name: "ClipCore"),
        .executableTarget(name: "clipultra", dependencies: ["ClipCore"]),
        .testTarget(name: "ClipCoreTests", dependencies: ["ClipCore"]),
    ]
)
