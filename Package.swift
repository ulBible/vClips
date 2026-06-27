// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vClips",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "vClips",
            path: "Sources/vClips"
        ),
        .testTarget(
            name: "vClipsTests",
            dependencies: ["vClips"],
            path: "Tests/vClipsTests"
        ),
    ]
)
