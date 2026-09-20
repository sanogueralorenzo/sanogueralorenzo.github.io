// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AgentMac", targets: ["AgentMac"])],
    targets: [
        .target(name: "AgentProtocol"),
        .executableTarget(name: "AgentMac", dependencies: ["AgentProtocol"]),
        .executableTarget(name: "AgentProtocolCheck", dependencies: ["AgentProtocol"]),
    ]
)
