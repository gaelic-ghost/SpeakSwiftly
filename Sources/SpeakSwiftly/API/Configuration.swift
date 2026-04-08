import Foundation

// MARK: - Runtime Configuration

public extension SpeakSwiftly {
    struct Configuration: Codable, Sendable {
        public let speechBackend: SpeakSwiftly.SpeechBackend
        public let textNormalizer: SpeakSwiftly.Normalizer?

        enum CodingKeys: String, CodingKey {
            case speechBackend
        }

        public init(
            speechBackend: SpeakSwiftly.SpeechBackend = .qwen3,
            textNormalizer: SpeakSwiftly.Normalizer? = nil
        ) {
            self.speechBackend = speechBackend
            self.textNormalizer = textNormalizer
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            speechBackend = try container.decode(SpeakSwiftly.SpeechBackend.self, forKey: .speechBackend)
            textNormalizer = nil
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(speechBackend, forKey: .speechBackend)
        }

        public static func load(from persistenceURL: URL) throws -> Self {
            let data = try Data(contentsOf: persistenceURL)
            return try makeDecoder().decode(Self.self, from: data)
        }

        public static func loadIfPresent(from persistenceURL: URL) throws -> Self? {
            guard FileManager.default.fileExists(atPath: persistenceURL.path) else {
                return nil
            }

            return try load(from: persistenceURL)
        }

        static func loadDefault(
            fileManager: FileManager = .default,
            profileRootOverride: String? = nil
        ) throws -> Self? {
            try loadIfPresent(
                from: defaultPersistenceURL(
                    fileManager: fileManager,
                    profileRootOverride: profileRootOverride
                )
            )
        }

        public func save(to persistenceURL: URL) throws {
            let directoryURL = persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(self)
            try data.write(to: persistenceURL, options: .atomic)
        }

        func saveDefault(
            fileManager: FileManager = .default,
            profileRootOverride: String? = nil
        ) throws {
            try save(
                to: Self.defaultPersistenceURL(
                    fileManager: fileManager,
                    profileRootOverride: profileRootOverride
                )
            )
        }

        static func defaultPersistenceURL(
            fileManager: FileManager = .default,
            profileRootOverride: String? = nil
        ) -> URL {
            ProfileStore.defaultConfigurationURL(
                fileManager: fileManager,
                profileRootOverride: profileRootOverride
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
    }
}

public extension SpeakSwiftly.Runtime {
    func status(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await submit(.status(id: requestID))
    }

    func switchSpeechBackend(
        to speechBackend: SpeakSwiftly.SpeechBackend,
        id requestID: String = UUID().uuidString
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.switchSpeechBackend(id: requestID, speechBackend: speechBackend))
    }

    func reloadModels(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await submit(.reloadModels(id: requestID))
    }

    func unloadModels(id requestID: String = UUID().uuidString) async -> SpeakSwiftly.RequestHandle {
        await submit(.unloadModels(id: requestID))
    }
}
