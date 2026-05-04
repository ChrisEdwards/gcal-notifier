// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GCalNotifierTools",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.61.1"),
        .package(url: "https://github.com/realm/SwiftLint", exact: "0.63.2"),
    ]
)
