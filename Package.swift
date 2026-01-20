// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-msgpack",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .library(
            name: "SwiftMsgpack",
            targets: ["SwiftMsgpack"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.53.8")
    ],
    targets: [
        .target(
            name: "SwiftMsgpack",
            dependencies: []
        ),
        .executableTarget(
            name: "example",
            dependencies: [
                "SwiftMsgpack",
            ],
            path: "Example"
        ),
        .testTarget(
            name: "SwiftMsgpackTests",
            dependencies: ["SwiftMsgpack"]
        ),
    ]
)
