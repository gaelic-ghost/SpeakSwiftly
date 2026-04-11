// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpeakSwiftly",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "SpeakSwiftlyCore",
            targets: ["SpeakSwiftlyCore"]
        ),
        .executable(
            name: "SpeakSwiftly",
            targets: ["SpeakSwiftlyCLI"]
        ),
        .executable(
            name: "SpeakSwiftlyTesting",
            targets: ["SpeakSwiftlyTesting"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/gaelic-ghost/TextForSpeech.git",
            .upToNextMajor(from: "0.15.0")
        ),
        .package(
            url: "https://github.com/Blaizzy/mlx-audio-swift.git",
            revision: "9264f40bc21c1dd461feb1ce1206e5ff38e8b9f5"
        )
    ],
    targets: [
        .target(
            name: "SpeakSwiftlyCore",
            dependencies: [
                .product(name: "TextForSpeech", package: "TextForSpeech"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift")
            ],
            path: "Sources/SpeakSwiftly",
            resources: [
                .copy("Resources/mlx-swift_Cmlx.bundle"),
            ]
        ),
        .executableTarget(
            name: "SpeakSwiftlyCLI",
            dependencies: ["SpeakSwiftlyCore"]
        ),
        .testTarget(
            name: "SpeakSwiftlyTests",
            dependencies: [
                "SpeakSwiftlyCore",
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ]
        ),
        .executableTarget(
            name: "SpeakSwiftlyTesting",
            dependencies: ["SpeakSwiftlyCore"]
        ),
    ]
)
