// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "A1RMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "A1RMac", targets: ["A1RMac"])],
    targets: [
        .target(name: "A1RProtocol"),
        .executableTarget(name: "A1RMac", dependencies: ["A1RProtocol"]),
        .executableTarget(name: "A1RProtocolCheck", dependencies: ["A1RProtocol"]),
    ]
)
