// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HASensorBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HASensorBarCore", targets: ["HASensorBarCore"]),
        .executable(name: "HASensorBarApp", targets: ["HASensorBarApp"])
    ],
    targets: [
        .target(name: "HASensorBarCore"),
        .executableTarget(name: "HASensorBarApp", dependencies: ["HASensorBarCore"]),
        .testTarget(
            name: "HASensorBarCoreTests",
            dependencies: ["HASensorBarCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
