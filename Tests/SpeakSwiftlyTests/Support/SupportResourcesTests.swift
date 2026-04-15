import Foundation
import SpeakSwiftly
import Testing

@Test func `vendored MLX bundle is present and readable`() throws {
    let mlxBundleURL = try SpeakSwiftly.SupportResources.mlxBundleURL()
    #expect(mlxBundleURL.lastPathComponent == "mlx-swift_Cmlx.bundle")

    let mlxBundle = try SpeakSwiftly.SupportResources.mlxBundle()
    #expect(mlxBundle.bundleURL == mlxBundleURL)
}

@Test func `vendored default metallib is present`() throws {
    let metallibURL = try SpeakSwiftly.SupportResources.defaultMetallibURL()
    #expect(metallibURL.lastPathComponent == "default.metallib")
    #expect(FileManager.default.fileExists(atPath: metallibURL.path))
}
