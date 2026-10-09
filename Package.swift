// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Autoeng",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Autoeng", targets: ["Autoeng"])],
    targets: [
        .target(name: "AutoengCore"),
        .executableTarget(name: "Autoeng", dependencies: ["AutoengCore"]),
        .testTarget(name: "AutoengCoreTests", dependencies: ["AutoengCore"])
    ]
)
