import Foundation

// MARK: - Runtime Configuration

public extension SpeakSwiftly {
    struct Configuration: Codable, Sendable, Equatable {
        public let speechBackend: SpeakSwiftly.SpeechBackend

        public init(speechBackend: SpeakSwiftly.SpeechBackend = .qwen3) {
            self.speechBackend = speechBackend
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

        public static func loadDefault(
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

        public func saveDefault(
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

        public static func defaultPersistenceURL(
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
