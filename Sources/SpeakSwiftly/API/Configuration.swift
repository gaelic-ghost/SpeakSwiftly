import Foundation

// MARK: - Runtime Configuration

public extension SpeakSwiftly {
    struct Configuration: Codable, Sendable {
        public enum LoadError: Swift.Error, LocalizedError, Sendable, Equatable {
            case fileNotFound(path: String)
            case unreadableFile(path: String, message: String)
            case invalidConfiguration(path: String, message: String)

            public var errorDescription: String? {
                switch self {
                case .fileNotFound(let path):
                    "SpeakSwiftly could not load configuration from '\(path)' because no file exists at that path."
                case .unreadableFile(let path, let message):
                    "SpeakSwiftly could not read configuration data from '\(path)'. \(message)"
                case .invalidConfiguration(let path, let message):
                    "SpeakSwiftly found configuration data at '\(path)', but it is not a valid SpeakSwiftly configuration. \(message)"
                }
            }
        }

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
                    message: error.localizedDescription
                )
            }

            do {
                return try makeDecoder().decode(Self.self, from: data)
            } catch {
                throw LoadError.invalidConfiguration(
                    path: fileURL.path,
                    message: error.localizedDescription
                )
            }
        }

        static func loadDefault(
            fileManager: FileManager = .default,
            profileRootOverride: String? = nil
        ) throws -> Self? {
            let persistenceURL = defaultPersistenceURL(
                fileManager: fileManager,
                profileRootOverride: profileRootOverride
            )
            guard fileManager.fileExists(atPath: persistenceURL.path) else {
                return nil
            }
            return try load(from: persistenceURL)
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
    func status() async -> SpeakSwiftly.RequestHandle {
        await submit(.status(id: UUID().uuidString))
    }

    func switchSpeechBackend(
        to speechBackend: SpeakSwiftly.SpeechBackend
    ) async -> SpeakSwiftly.RequestHandle {
        await submit(.switchSpeechBackend(id: UUID().uuidString, speechBackend: speechBackend))
    }

    func reloadModels() async -> SpeakSwiftly.RequestHandle {
        await submit(.reloadModels(id: UUID().uuidString))
    }

    func unloadModels() async -> SpeakSwiftly.RequestHandle {
        await submit(.unloadModels(id: UUID().uuidString))
    }
}
