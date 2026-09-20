// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentMac",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "AgentMac", targets: ["AgentMac"])],
    targets: [
        .target(name: "AgentProtocol"),
        .target(name: "AgentClient", dependencies: ["AgentProtocol"]),
        .executableTarget(name: "AgentMac", dependencies: ["AgentClient", "AgentProtocol"]),
        .executableTarget(name: "AgentCheck", dependencies: ["AgentClient", "AgentProtocol"]),
    ]
)
