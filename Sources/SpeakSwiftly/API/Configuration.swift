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

    /// Selects whether SpeakSwiftly should lower supported macOS media app volumes while local playback is active.
    enum DuckMediaVolume: String, Codable, Sendable, Equatable, CaseIterable {
        case off
        case aLittle = "a_little"
        case `default`
        case aLot = "a_lot"

        /// Suggested app-tier `NSAppleEventsUsageDescription` copy for consumers that enable media-app ducking.
        public static let automationUsageDescription =
            "SpeakSwiftly needs permission to adjust Spotify and Music volume while local speech playback is active, then restore the original volume afterward."

        /// Returns whether this setting needs macOS Automation permission to control supported media apps.
        public var requiresMediaAutomation: Bool {
            self != .off
        }
    }

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
            case defaultVoiceProfile
            case duckMediaVolume
            case audioOutputDestination
            case recentGeneratedAudioLimit
        }

        /// The speech backend to activate when the runtime starts.
        public let speechBackend: SpeakSwiftly.SpeechBackend
        /// The Qwen conditioning strategy to use for Qwen-backed generation.
        public let qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy
        /// The stored voice profile used when callers do not choose one explicitly.
        public let defaultVoiceProfile: SpeakSwiftly.Name
        /// The supported media-app ducking strength to apply while SpeakSwiftly playback is active.
        public let duckMediaVolume: SpeakSwiftly.DuckMediaVolume
        /// The generated-audio destination to activate for live speech requests.
        public let audioOutputDestination: SpeakSwiftly.AudioOutputDestination
        /// The number of recent live generated-audio items to keep in memory for replay.
        public let recentGeneratedAudioLimit: Int
        /// Extra bundled system-profile roots supplied by host packages at startup.
        public let systemProfileResourceRoots: [URL]
        /// An optional text normalizer to reuse instead of creating the default one.
        public let textNormalizer: SpeakSwiftly.Normalizer?

        /// Creates a runtime configuration value.
        public init(
            speechBackend: SpeakSwiftly.SpeechBackend = .qwen3_smol,
            qwenConditioningStrategy: SpeakSwiftly.QwenConditioningStrategy = .preparedConditioning,
            defaultVoiceProfile: SpeakSwiftly.Name = SpeakSwiftly.DefaultVoiceProfiles.signal,
            duckMediaVolume: SpeakSwiftly.DuckMediaVolume = .off,
            audioOutputDestination: SpeakSwiftly.AudioOutputDestination = .localPlayback,
            recentGeneratedAudioLimit: Int = 5,
            systemProfileResourceRoots: [URL] = [],
            textNormalizer: SpeakSwiftly.Normalizer? = nil,
        ) {
            self.speechBackend = speechBackend
            self.qwenConditioningStrategy = qwenConditioningStrategy
            self.defaultVoiceProfile = Self.normalizedDefaultVoiceProfile(defaultVoiceProfile)
            self.duckMediaVolume = duckMediaVolume
            self.audioOutputDestination = audioOutputDestination
            self.recentGeneratedAudioLimit = Self.normalizedRecentGeneratedAudioLimit(recentGeneratedAudioLimit)
            self.systemProfileResourceRoots = systemProfileResourceRoots.map(\.standardizedFileURL)
            self.textNormalizer = textNormalizer
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            speechBackend = try container.decode(SpeakSwiftly.SpeechBackend.self, forKey: .speechBackend)
            qwenConditioningStrategy = try container.decodeIfPresent(
                SpeakSwiftly.QwenConditioningStrategy.self,
                forKey: .qwenConditioningStrategy,
            ) ?? .preparedConditioning
            defaultVoiceProfile = try Self.normalizedDefaultVoiceProfile(
                container.decodeIfPresent(
                    SpeakSwiftly.Name.self,
                    forKey: .defaultVoiceProfile,
                ),
            )
            duckMediaVolume = try container.decodeIfPresent(
                SpeakSwiftly.DuckMediaVolume.self,
                forKey: .duckMediaVolume,
            ) ?? .off
            audioOutputDestination = try container.decodeIfPresent(
                SpeakSwiftly.AudioOutputDestination.self,
                forKey: .audioOutputDestination,
            ) ?? .localPlayback
            recentGeneratedAudioLimit = try Self.normalizedRecentGeneratedAudioLimit(
                container.decodeIfPresent(
                    Int.self,
                    forKey: .recentGeneratedAudioLimit,
                ) ?? 5,
            )
            systemProfileResourceRoots = []
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

        static func normalizedRecentGeneratedAudioLimit(_ limit: Int) -> Int {
            min(8, max(0, limit))
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
            try container.encode(defaultVoiceProfile, forKey: .defaultVoiceProfile)
            try container.encode(duckMediaVolume, forKey: .duckMediaVolume)
            try container.encode(audioOutputDestination, forKey: .audioOutputDestination)
            try container.encode(recentGeneratedAudioLimit, forKey: .recentGeneratedAudioLimit)
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

    /// Subscribes to sequenced runtime-state updates.
    func updates() -> AsyncStream<SpeakSwiftly.RuntimeUpdate> {
        runtimeUpdates()
    }

    /// Returns a point-in-time read of runtime resident-model and storage state.
    func snapshot() -> SpeakSwiftly.RuntimeSnapshot {
        runtimeSnapshot()
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
