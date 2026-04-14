import Foundation

// MARK: - Bundled Runtime Resources

public extension SpeakSwiftly {
    /// Looks up the vendored runtime resources that SpeakSwiftly needs for MLX-backed execution.
    enum SupportResources {
        /// Errors that can occur while locating bundled runtime resources.
        public enum LookupError: Swift.Error, LocalizedError, Sendable, Equatable {
            case missingMLXBundle(expectedPath: String)
            case unreadableMLXBundle(path: String)
            case missingDefaultMetallib(expectedPath: String)

            // MARK: Computed Properties

            public var errorDescription: String? {
                switch self {
                    case let .missingMLXBundle(expectedPath):
                        "SpeakSwiftly expected its vendored MLX shader bundle at '\(expectedPath)', but no bundle exists there."
                    case let .unreadableMLXBundle(path):
                        "SpeakSwiftly found an MLX shader bundle at '\(path)', but Foundation could not open it as a readable bundle."
                    case let .missingDefaultMetallib(expectedPath):
                        "SpeakSwiftly expected the vendored MLX metallib at '\(expectedPath)', but that file is missing."
                }
            }
        }

        /// The package resource bundle for the SpeakSwiftly target.
        public static let bundle: Bundle = .module

        /// Returns the vendored MLX bundle URL.
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

        /// Opens the vendored MLX bundle as a Foundation bundle.
        public static func mlxBundle() throws -> Bundle {
            let url = try mlxBundleURL()
            guard let bundle = Bundle(url: url) else {
                throw LookupError.unreadableMLXBundle(path: url.path)
            }

            return bundle
        }

        /// Returns the vendored default Metal library used by the MLX bundle.
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
