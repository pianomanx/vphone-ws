// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vphone-ws",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "VPhoneWSCore", path: "Sources/VPhoneWSCore"),
        .executableTarget(
            name: "vphone-ws",
            dependencies: ["VPhoneWSCore"],
            path: "Sources/vphone-ws"),
        .testTarget(
            name: "VPhoneWSCoreTests",
            dependencies: ["VPhoneWSCore"],
            path: "tests/VPhoneWSCoreTests"),
    ]
)
