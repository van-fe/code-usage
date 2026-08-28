// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeUsage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodeUsage", targets: ["CodeUsage"])
    ],
    targets: [
        .executableTarget(
            name: "CodeUsage",
            linkerSettings: [
                .linkedFramework("CloudKit"),
                .linkedFramework("Security")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
