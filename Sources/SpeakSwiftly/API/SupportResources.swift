import Foundation

// MARK: - Bundled Runtime Resources

public extension SpeakSwiftly {
    enum SupportResources {
        public enum LookupError: Swift.Error, LocalizedError, Sendable, Equatable {
            case missingMLXBundle(expectedPath: String)
            case unreadableMLXBundle(path: String)
            case missingDefaultMetallib(expectedPath: String)

            public var errorDescription: String? {
                switch self {
                case .missingMLXBundle(let expectedPath):
                    "SpeakSwiftly expected its vendored MLX shader bundle at '\(expectedPath)', but no bundle exists there."
                case .unreadableMLXBundle(let path):
                    "SpeakSwiftly found an MLX shader bundle at '\(path)', but Foundation could not open it as a readable bundle."
                case .missingDefaultMetallib(let expectedPath):
                    "SpeakSwiftly expected the vendored MLX metallib at '\(expectedPath)', but that file is missing."
                }
            }
        }

        public static let bundle: Bundle = .module

        public static func mlxBundleURL() throws -> URL {
            let expectedURL = bundle.resourceURL?
                .appendingPathComponent("mlx-swift_Cmlx.bundle", isDirectory: true)
                .standardizedFileURL

            guard let expectedURL else {
                throw LookupError.missingMLXBundle(expectedPath: bundle.bundleURL.path)
            }

            guard FileManager.default.fileExists(atPath: expectedURL.path) else {
                throw LookupError.missingMLXBundle(expectedPath: expectedURL.path)
            }

            return expectedURL
        }

        public static func mlxBundle() throws -> Bundle {
            let url = try mlxBundleURL()
            guard let bundle = Bundle(url: url) else {
                throw LookupError.unreadableMLXBundle(path: url.path)
            }
            return bundle
        }

        public static func defaultMetallibURL() throws -> URL {
            let bundle = try mlxBundle()
            guard let resourceURL = bundle.resourceURL else {
                throw LookupError.missingDefaultMetallib(expectedPath: bundle.bundleURL.path)
            }

            let metallibURL = resourceURL
                .appendingPathComponent("default.metallib", isDirectory: false)
                .standardizedFileURL

            guard FileManager.default.fileExists(atPath: metallibURL.path) else {
                throw LookupError.missingDefaultMetallib(expectedPath: metallibURL.path)
            }

            return metallibURL
        }
    }
}
