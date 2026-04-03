// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpeakSwiftly",
    platforms: [
        .macOS("15.0"),
    ],
    products: [
        .library(
            name: "SpeakSwiftlyLibrary",
            targets: ["SpeakSwiftly"]
        ),
        .executable(
            name: "SpeakSwiftly",
            targets: ["SpeakSwiftlyCLI"]
        ),
    ],
    dependencies: [
    .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main")    
    ],
    targets: [
        .target(
            name: "SpeakSwiftly",
            dependencies: [
            .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
            .product(name: "MLXAudioCore", package: "mlx-audio-swift")
            ]
        ),
        .executableTarget(
            name: "SpeakSwiftlyCLI",
            dependencies: ["SpeakSwiftly"]
        ),
        .testTarget(
            name: "SpeakSwiftlyTests",
            dependencies: [ "SpeakSwiftly" ]
        ),
    ]
)
