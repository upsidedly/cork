// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cork",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cork", targets: ["Cork"]),
        .executable(name: "cork-mcp", targets: ["CorkMCP"])
    ],
    targets: [
        .target(name: "CorkCore"),
        .target(name: "CorkInput", linkerSettings: [.linkedFramework("CoreFoundation")]),
        .executableTarget(name: "Cork", dependencies: ["CorkCore", "CorkInput"]),
        .executableTarget(name: "CorkMCP", dependencies: ["CorkCore"]),
        .executableTarget(name: "CorkChecks", dependencies: ["CorkCore"], path: "Tests/CorkCoreTests")
    ],
    swiftLanguageModes: [.v6]
)
