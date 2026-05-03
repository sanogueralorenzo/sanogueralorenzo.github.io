// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexMenuBar", targets: ["CodexMenuBar"])
    ],
    targets: [
        .executableTarget(name: "CodexMenuBar")
    ]
)
