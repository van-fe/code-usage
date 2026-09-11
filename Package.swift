// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeUsage",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodeUsage", targets: ["CodeUsage"]),
        .executable(name: "CodeUsageWidgets", targets: ["CodeUsageWidgets"])
    ],
    targets: [
        .target(
            name: "CodeUsageDisplay"
        ),
        .executableTarget(
            name: "CodeUsage",
            dependencies: ["CodeUsageDisplay"],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("CloudKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "CodeUsageWidgets",
            dependencies: ["CodeUsageDisplay"],
            linkerSettings: [
                .linkedFramework("AppIntents"),
                .linkedFramework("WidgetKit"),
                // WidgetKit extensions must enter through Foundation's extension
                // bootstrap. SwiftPM executable targets otherwise use Swift main,
                // so chronod sees the process exit before descriptors are returned.
                .unsafeFlags([
                    "-Xlinker", "-e",
                    "-Xlinker", "_NSExtensionMain"
                ])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
