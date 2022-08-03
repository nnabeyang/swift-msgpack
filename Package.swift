// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-msgpack",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [
        .library(
            name: "SwiftMsgpack",
            targets: ["SwiftMsgpack"]
        ),
    ],
    dependencies: [],
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
