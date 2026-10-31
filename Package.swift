// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cork",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cork", targets: ["Cork"]),
        .executable(name: "cork-mcp", targets: ["CorkMCP"]),
        .executable(name: "cork-importer", targets: ["CorkImporter"])
    ],
    targets: [
        .target(name: "CorkCore"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "CorkImportCore", dependencies: ["CorkCore", "CSQLite"]),
        .target(name: "CorkInput", linkerSettings: [.linkedFramework("CoreFoundation")]),
        .executableTarget(name: "Cork", dependencies: ["CorkCore", "CorkInput"]),
        .executableTarget(name: "CorkMCP", dependencies: ["CorkCore"]),
        .executableTarget(name: "CorkImporter", dependencies: ["CorkCore", "CorkImportCore"]),
        .executableTarget(name: "CorkImportChecks", dependencies: ["CorkCore", "CorkImportCore", "CSQLite"], path: "Tests/CorkImportTests"),
        .executableTarget(name: "CorkChecks", dependencies: ["CorkCore"], path: "Tests/CorkCoreTests")
    ],
    swiftLanguageModes: [.v6]
)
