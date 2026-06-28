// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpeakSwiftly",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "SpeakSwiftly",
            targets: ["SpeakSwiftly"],
        ),
        .library(
            name: "SpeakSwiftlyCore",
            targets: ["SpeakSwiftlyCore"],
        ),
        .library(
            name: "SpeakSwiftlyPlayback",
            targets: ["SpeakSwiftlyPlayback"],
        ),
        .library(
            name: "SpeakSwiftlyHTTPAudioOutput",
            targets: ["SpeakSwiftlyHTTPAudioOutput"],
        ),
        .library(
            name: "SpeakSwiftlyFileAudioOutput",
            targets: ["SpeakSwiftlyFileAudioOutput"],
        ),
        .library(
            name: "SpeakSwiftlyNetworkAudioOutput",
            targets: ["SpeakSwiftlyNetworkAudioOutput"],
        ),
        .executable(
            name: "SpeakSwiftlyTool",
            targets: ["SpeakSwiftlyTool"],
        ),
        .executable(
            name: "SpeakSwiftlyProbeTool",
            targets: ["SpeakSwiftlyProbeTool"],
        ),
        .plugin(
            name: "UpsertSystemVoiceProfile",
            targets: ["UpsertSystemVoiceProfile"],
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/gaelic-ghost/TextForSpeech.git",
            .upToNextMajor(from: "0.23.0"),
        ),
        .package(
            url: "https://github.com/gaelic-ghost/mlx-audio-swift.git",
            exact: "0.101.0-gaelic.1",
        ),
        .package(
            url: "https://github.com/ml-explore/mlx-swift.git",
            .upToNextMajor(from: "0.30.6"),
        ),
        .package(
            url: "https://github.com/apple/swift-nio.git",
            .upToNextMajor(from: "2.97.1"),
        ),
    ],
    targets: [
        .target(
            name: "SpeakSwiftly",
            dependencies: [
                "SpeakSwiftlyAudioSupport",
                "SpeakSwiftlyCore",
                "SpeakSwiftlyQwenGeneration",
                "SpeakSwiftlyPlayback",
                "SpeakSwiftlyHTTPAudioOutput",
                "SpeakSwiftlyFileAudioOutput",
                "SpeakSwiftlyNetworkAudioOutput",
                .product(name: "TextForSpeech", package: "TextForSpeech"),
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ],
            path: "Sources/SpeakSwiftly",
            resources: [
                .copy("Resources/mlx-swift_Cmlx.bundle"),
                .copy("Resources/SystemProfiles"),
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
            ],
        ),
        .target(
            name: "SpeakSwiftlyCore",
        ),
        .target(
            name: "SpeakSwiftlyQwenGeneration",
            dependencies: [
                "SpeakSwiftlyCore",
            ],
        ),
        .target(
            name: "SpeakSwiftlyPlayback",
            dependencies: [
                "SpeakSwiftlyAudioSupport",
                "SpeakSwiftlyCore",
            ],
        ),
        .target(
            name: "SpeakSwiftlyAudioSupport",
            dependencies: [
                "SpeakSwiftlyCore",
            ],
        ),
        .target(
            name: "SpeakSwiftlyHTTPAudioOutput",
            dependencies: [
                "SpeakSwiftlyCore",
            ],
        ),
        .target(
            name: "SpeakSwiftlyFileAudioOutput",
            dependencies: [
                "SpeakSwiftlyAudioSupport",
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ],
        ),
        .target(
            name: "SpeakSwiftlyNetworkAudioOutput",
            dependencies: [
                "SpeakSwiftlyCore",
                .product(name: "NIOCore", package: "swift-nio"),
            ],
        ),
        .executableTarget(
            name: "SpeakSwiftlyTool",
            dependencies: [
                "SpeakSwiftly",
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ],
        ),
        .plugin(
            name: "UpsertSystemVoiceProfile",
            capability: .command(
                intent: .custom(
                    verb: "upsert-system-voice-profile",
                    description: "Insert or update a SpeakSwiftly system voice profile in a target resource bundle",
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Generated system voice profiles are durable package resources inserted or updated in the consumer target.",
                    ),
                ],
            ),
            dependencies: [
                "SpeakSwiftlyTool",
            ],
        ),
        .testTarget(
            name: "SpeakSwiftlyTests",
            dependencies: [
                "SpeakSwiftly",
                "SpeakSwiftlyAudioSupport",
                "SpeakSwiftlyCore",
                "SpeakSwiftlyPlayback",
                "SpeakSwiftlyHTTPAudioOutput",
                "SpeakSwiftlyFileAudioOutput",
                "SpeakSwiftlyNetworkAudioOutput",
                "SpeakSwiftlyTool",
                "SpeakSwiftlyTestSupport",
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ],
            resources: [
                .copy("Resources/default.metallib"),
                .copy("Resources/E2EProfiles"),
            ],
        ),
        .target(
            name: "SpeakSwiftlyTestSupport",
        ),
        .executableTarget(
            name: "SpeakSwiftlyProbeTool",
            dependencies: [
                "SpeakSwiftly",
                "SpeakSwiftlyTestSupport",
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
            ],
            linkerSettings: [
                .linkedFramework("CoreML", .when(platforms: [.macOS])),
            ],
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ],
)
