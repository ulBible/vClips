// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vClips",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "vClips",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/vClips"
        ),
        .testTarget(
            name: "vClipsTests",
            dependencies: [
                "vClips",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Tests/vClipsTests"
        ),
    ]
)
