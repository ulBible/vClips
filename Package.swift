// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vClips",
    platforms: [.macOS(.v14)],
    products: [
        // GitHub-release variant: Sparkle auto-updates + donation link.
        .executable(name: "vClips", targets: ["vClips"]),
        // Mac App Store variant: sandboxed, no Sparkle, no donation link.
        .executable(name: "vClipsAppStore", targets: ["vClipsAppStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Everything except the entry points, so the App Store variant can
        // share the app without linking Sparkle.
        .target(
            name: "vClipsCore",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/vClipsCore"
        ),
        .executableTarget(
            name: "vClips",
            dependencies: [
                "vClipsCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/vClips"
        ),
        .executableTarget(
            name: "vClipsAppStore",
            dependencies: [
                "vClipsCore",
            ],
            path: "Sources/vClipsAppStore"
        ),
        .testTarget(
            name: "vClipsTests",
            dependencies: [
                "vClipsCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Tests/vClipsTests"
        ),
    ]
)
