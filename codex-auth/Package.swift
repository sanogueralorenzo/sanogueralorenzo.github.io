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

let package = Package(
    name: "CodexAuth",
    products: products,
    targets: targets
)
