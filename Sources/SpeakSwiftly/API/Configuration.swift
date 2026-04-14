import Foundation

// MARK: - Runtime Configuration

public extension SpeakSwiftly {
    /// Selects how Qwen-specific conditioning artifacts are prepared before generation.
    enum QwenConditioningStrategy: String, Codable, Sendable, Equatable, CaseIterable {
        case legacyRaw = "legacy_raw"
        case preparedConditioning = "prepared_conditioning"
    }

    // MARK: Configuration

    /// Startup configuration for a SpeakSwiftly runtime.
    struct Configuration: Codable, Sendable {
        // MARK: Load Error

        /// Errors that can occur while loading persisted runtime configuration.
        public enum LoadError: Swift.Error, LocalizedError, Sendable, Equatable {
            case fileNotFound(path: String)
            case unreadableFile(path: String, message: String)
            case invalidConfiguration(path: String, message: String)

            // MARK: Computed Properties

            public var errorDescription: String? {
                switch self {
                    case let .fileNotFound(path):
                        "SpeakSwiftly could not load configuration from '\(path)' because no file exists at that path."
                    case let .unreadableFile(path, message):
                        "SpeakSwiftly could not read configuration data from '\(path)'. \(message)"
                    case let .invalidConfiguration(path, message):
                        "SpeakSwiftly found configuration data at '\(path)', but it is not a valid SpeakSwiftly configuration. \(message)"
                }
            }
        }

        enum CodingKeys: String, CodingKey {
            case speechBackend
            case qwenConditioningStrategy
        }

        /// The speech backend to activate when the runtime starts.
        public let speechBackend: SpeakSwiftly.SpeechBackend
        /// The Qwen conditioning strategy to use for Qwen-backed generation.
        public let qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy
        /// An optional text normalizer to reuse instead of creating the default one.
        public let textNormalizer: SpeakSwiftly.Normalizer?

        /// Creates a runtime configuration value.
        public init(
            speechBackend: SpeakSwiftly.SpeechBackend = .qwen3,
            qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy = .legacyRaw,
            textNormalizer: SpeakSwiftly.Normalizer? = nil,
        ) {
            self.speechBackend = speechBackend
            self.qwenConditioningStrategy = qwenConditioningStrategy
            self.textNormalizer = textNormalizer
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            speechBackend = try container.decode(SpeakSwiftly.SpeechBackend.self, forKey: .speechBackend)
            qwenConditioningStrategy = try container.decodeIfPresent(
                SpeakSwiftly.QwenConditioningStrategy.self,
                forKey: .qwenConditioningStrategy,
            ) ?? .legacyRaw
            textNormalizer = nil
        }

        /// Loads a persisted configuration value from disk.
        public static func load(from persistenceURL: URL) throws -> Self {
            let fileURL = persistenceURL.standardizedFileURL
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw LoadError.fileNotFound(path: fileURL.path)
            }

            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw LoadError.unreadableFile(
                    path: fileURL.path,
                    message: error.localizedDescription,
                )
            }

            do {
                return try makeDecoder().decode(Self.self, from: data)
            } catch {
                throw LoadError.invalidConfiguration(
                    path: fileURL.path,
                    message: error.localizedDescription,
                )
            }
        }

        static func loadDefault(
            fileManager: FileManager = .default,
            profileRootOverride: String? = nil,
        ) throws -> Self? {
            let persistenceURL = defaultPersistenceURL(
                fileManager: fileManager,
                profileRootOverride: profileRootOverride,
            )
            guard fileManager.fileExists(atPath: persistenceURL.path) else {
                return nil
            }

            return try load(from: persistenceURL)
        }

        static func defaultPersistenceURL(
            fileManager: FileManager = .default,
            profileRootOverride: String? = nil,
        ) -> URL {
            ProfileStore.defaultConfigurationURL(
                fileManager: fileManager,
                profileRootOverride: profileRootOverride,
            )
        }

        private static func makeEncoder() -> JSONEncoder {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return encoder
        }

        private static func makeDecoder() -> JSONDecoder {
            JSONDecoder()
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(speechBackend, forKey: .speechBackend)
            try container.encode(qwenConditioningStrategy, forKey: .qwenConditioningStrategy)
        }

        /// Saves this configuration value to disk.
        public func save(to persistenceURL: URL) throws {
            let directoryURL = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(self)
            try data.write(to: persistenceURL, options: .atomic)
        }

        func saveDefault(
            fileManager: FileManager = .default,
            profileRootOverride: String? = nil,
        ) throws {
            try save(
                to: Self.defaultPersistenceURL(
                    fileManager: fileManager,
                    profileRootOverride: profileRootOverride,
                ),
            )
        }
    }
}

public extension SpeakSwiftly.Runtime {
    // MARK: Runtime Control

    /// Retrieves a compact runtime status snapshot.
    func status() async -> SpeakSwiftly.RequestHandle {
        await submit(.status(id: UUID().uuidString))
    }

    /// Retrieves a richer runtime overview snapshot.
    func overview() async -> SpeakSwiftly.RequestHandle {
        await submit(.overview(id: UUID().uuidString))
    }

    /// Switches the active speech backend for the running runtime.
    func switchSpeechBackend(
        to speechBackend: SpeakSwiftly.SpeechBackend,
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.switchSpeechBackend(id: UUID().uuidString, speechBackend: speechBackend))
    }

    /// Reloads resident speech models for the active backend.
    func reloadModels() async -> SpeakSwiftly.RequestHandle {
        await submit(.reloadModels(id: UUID().uuidString))
    }

    /// Unloads resident speech models for the active backend.
    func unloadModels() async -> SpeakSwiftly.RequestHandle {
        await submit(.unloadModels(id: UUID().uuidString))
    }
}
