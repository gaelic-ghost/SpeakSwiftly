import Foundation

// MARK: - Runtime Configuration

public extension SpeakSwiftly {
    /// Stable names for package-recognized built-in voice profiles.
    enum DefaultVoiceProfiles {
        public static let signal: SpeakSwiftly.Name = "swift-signal"
        public static let anchor: SpeakSwiftly.Name = "swift-anchor"
    }

    /// Selects how Qwen-specific conditioning artifacts are prepared before generation.
    enum QwenConditioningStrategy: String, Codable, Sendable, Equatable, CaseIterable {
        case legacyRaw = "legacy_raw"
        case preparedConditioning = "prepared_conditioning"
    }

    /// Selects the resident Qwen model loaded for Qwen-backed speech generation.
    enum QwenResidentModel: String, Codable, Sendable, Equatable, CaseIterable {
        case base06B8Bit = "base_0_6b_8bit"
        case base17B8Bit = "base_1_7b_8bit"
    }

    /// Selects how resident Marvis model instances are kept warm.
    enum MarvisResidentPolicy: String, Codable, Sendable, Equatable, CaseIterable {
        /// Keep both conversational resident model objects warm, but serialize
        /// Marvis generation so only one request uses the model path at a time.
        case dualResidentSerialized = "dual_resident_serialized"
        /// Keep a single Marvis resident model object warm and reuse it for
        /// whichever conversational voice a request needs next.
        case singleResidentDynamic = "single_resident_dynamic"
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
            case qwenResidentModel
            case marvisResidentPolicy
            case defaultVoiceProfile
        }

        /// The speech backend to activate when the runtime starts.
        public let speechBackend: SpeakSwiftly.SpeechBackend
        /// The Qwen conditioning strategy to use for Qwen-backed generation.
        public let qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy
        /// The resident Qwen model to load for Qwen-backed generation.
        public let qwenResidentModel: SpeakSwiftly.QwenResidentModel
        /// The resident Marvis loading policy to use for Marvis-backed generation.
        public let marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy
        /// The stored voice profile used when callers do not choose one explicitly.
        public let defaultVoiceProfile: SpeakSwiftly.Name
        /// An optional text normalizer to reuse instead of creating the default one.
        public let textNormalizer: SpeakSwiftly.Normalizer?

        /// Creates a runtime configuration value.
        public init(
            speechBackend: SpeakSwiftly.SpeechBackend = .qwen3,
            qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy = .preparedConditioning,
            qwenResidentModel: SpeakSwiftly.QwenResidentModel = .base06B8Bit,
            marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy = .dualResidentSerialized,
            defaultVoiceProfile: SpeakSwiftly.Name = SpeakSwiftly.DefaultVoiceProfiles.signal,
            textNormalizer: SpeakSwiftly.Normalizer? = nil,
        ) {
            self.speechBackend = speechBackend
            self.qwenConditioningStrategy = qwenConditioningStrategy
            self.qwenResidentModel = qwenResidentModel
            self.marvisResidentPolicy = marvisResidentPolicy
            self.defaultVoiceProfile = Self.normalizedDefaultVoiceProfile(defaultVoiceProfile)
            self.textNormalizer = textNormalizer
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            speechBackend = try container.decode(SpeakSwiftly.SpeechBackend.self, forKey: .speechBackend)
            qwenConditioningStrategy = try container.decodeIfPresent(
                SpeakSwiftly.QwenConditioningStrategy.self,
                forKey: .qwenConditioningStrategy,
            ) ?? .preparedConditioning
            qwenResidentModel = try container.decodeIfPresent(
                SpeakSwiftly.QwenResidentModel.self,
                forKey: .qwenResidentModel,
            ) ?? .base06B8Bit
            marvisResidentPolicy = try container.decodeIfPresent(
                SpeakSwiftly.MarvisResidentPolicy.self,
                forKey: .marvisResidentPolicy,
            ) ?? .dualResidentSerialized
            defaultVoiceProfile = try Self.normalizedDefaultVoiceProfile(
                container.decodeIfPresent(
                    SpeakSwiftly.Name.self,
                    forKey: .defaultVoiceProfile,
                ),
            )
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
            stateRootOverride: String? = nil,
        ) throws -> Self? {
            let persistenceURL = defaultPersistenceURL(
                fileManager: fileManager,
                stateRootOverride: stateRootOverride,
            )
            guard fileManager.fileExists(atPath: persistenceURL.path) else {
                return nil
            }

            return try load(from: persistenceURL)
        }

        static func defaultPersistenceURL(
            fileManager: FileManager = .default,
            stateRootOverride: String? = nil,
        ) -> URL {
            ProfileStore.defaultConfigurationURL(
                fileManager: fileManager,
                stateRootOverride: stateRootOverride,
            )
        }

        static func normalizedDefaultVoiceProfile(_ profileName: SpeakSwiftly.Name?) -> SpeakSwiftly.Name {
            let trimmed = profileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? SpeakSwiftly.DefaultVoiceProfiles.signal : trimmed
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
            try container.encode(qwenResidentModel, forKey: .qwenResidentModel)
            try container.encode(marvisResidentPolicy, forKey: .marvisResidentPolicy)
            try container.encode(defaultVoiceProfile, forKey: .defaultVoiceProfile)
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
            stateRootOverride: String? = nil,
        ) throws {
            try save(
                to: Self.defaultPersistenceURL(
                    fileManager: fileManager,
                    stateRootOverride: stateRootOverride,
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

    /// Returns the voice profile name used when a caller omits an explicit voice profile.
    var defaultVoiceProfile: SpeakSwiftly.Name {
        defaultVoiceProfileName
    }

    /// Sets and persists the voice profile name used when a caller omits an explicit voice profile.
    func setDefaultVoiceProfile(_ profileName: SpeakSwiftly.Name) throws {
        try setDefaultVoiceProfileName(profileName)
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
