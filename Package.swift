// swift-tools-version: 6.3
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
            .upToNextMajor(from: "0.22.0"),
        ),
        .package(
            url: "https://github.com/gaelic-ghost/mlx-audio-swift.git",
            exact: "0.99.0",
        ),
        .package(
            url: "https://github.com/ml-explore/mlx-swift.git",
            .upToNextMajor(from: "0.30.6"),
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
                .copy("Resources/SystemProfiles"),
            ],
            linkerSettings: [
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
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
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ],
)
