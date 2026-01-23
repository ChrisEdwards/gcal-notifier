// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GCalNotifier",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "GCalNotifier", targets: ["GCalNotifier"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "GCalNotifier",
            dependencies: ["GCalNotifierCore", "KeyboardShortcuts", "MenuBarExtraAccess"],
            path: "Sources/GCalNotifier",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "GCalNotifierCore",
            dependencies: [],
            path: "Sources/GCalNotifierCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "GCalNotifierTests",
            dependencies: ["GCalNotifierCore"],
            path: "Tests/GCalNotifierTests"
        ),
    ]
)
