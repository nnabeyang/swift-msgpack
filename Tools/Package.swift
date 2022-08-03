// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "Tools",
    platforms: [.macOS(.v10_11)],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.49.14"),
    ],
    targets: [.target(name: "Tools", path: "")]
)
