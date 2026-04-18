// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpeakSwiftly",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "SpeakSwiftly",
            targets: ["SpeakSwiftly"],
        ),
        .executable(
            name: "SpeakSwiftlyTool",
            targets: ["SpeakSwiftlyTool"],
        ),
        .executable(
            name: "SpeakSwiftlyTesting",
            targets: ["SpeakSwiftlyTesting"],
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/gaelic-ghost/TextForSpeech.git",
            .upToNextMajor(from: "0.17.2"),
        ),
        .package(
            url: "https://github.com/gaelic-ghost/mlx-audio-swift.git",
            from: "69.2.0",
        ),
    ],
    targets: [
        .target(
            name: "SpeakSwiftly",
            dependencies: [
                .product(name: "TextForSpeech", package: "TextForSpeech"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ],
            path: "Sources/SpeakSwiftly",
            resources: [
                .copy("Resources/mlx-swift_Cmlx.bundle"),
            ],
        ),
        .executableTarget(
            name: "SpeakSwiftlyTool",
            dependencies: ["SpeakSwiftly"],
        ),
        .testTarget(
            name: "SpeakSwiftlyTests",
            dependencies: [
                "SpeakSwiftly",
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ],
        ),
        .executableTarget(
            name: "SpeakSwiftlyTesting",
            dependencies: ["SpeakSwiftly"],
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ],
)
