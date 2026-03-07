// swift-tools-version: 6.2
import PackageDescription

var products: [Product] = [
    .library(name: "CodexAuthCore", targets: ["CodexAuthCore"]),
    .executable(name: "codex-auth", targets: ["CodexAuthCLI"])
]

var targets: [Target] = [
    .target(name: "CodexAuthCore"),
    .executableTarget(
        name: "CodexAuthCLI",
        dependencies: ["CodexAuthCore"]
    )
]

#if os(macOS)
products.append(.executable(name: "CodexAuthMenuBar", targets: ["CodexAuthMenuBar"]))
targets.append(
    .executableTarget(
        name: "CodexAuthMenuBar",
        dependencies: ["CodexAuthCore"]
    )
)
#endif

let package = Package(
    name: "CodexAuth",
    products: products,
    targets: targets
)
