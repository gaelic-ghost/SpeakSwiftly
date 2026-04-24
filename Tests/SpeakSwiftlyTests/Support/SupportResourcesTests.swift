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

@Test func `e2e profile fixtures are bundled`() throws {
    let resourceURL = try #require(Bundle.module.resourceURL)
    let profilesURL = resourceURL
        .appendingPathComponent("E2EProfiles", isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let expectedProfiles = [
        "e2e-femme-design",
        "e2e-masc-clone-inferred",
        "e2e-masc-clone-provided",
        "e2e-masc-design",
    ]

    for profileName in expectedProfiles {
        let profileURL = profilesURL.appendingPathComponent(profileName, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: profileURL.appendingPathComponent("profile.json").path))
        #expect(FileManager.default.fileExists(atPath: profileURL.appendingPathComponent("reference.wav").path))
    }
}
