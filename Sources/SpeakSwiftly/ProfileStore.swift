import Foundation

// MARK: - Profile Models

struct ProfileManifest: Codable, Sendable, Equatable {
    let version: Int
    let profileName: String
    let createdAt: Date
    let modelRepo: String
    let voiceDescription: String
    let sourceText: String
    let referenceAudioFile: String
    let sampleRate: Int
}

public extension SpeakSwiftly {
    struct ProfileSummary: Codable, Sendable, Equatable {
        public let profileName: String
        public let createdAt: Date
        public let voiceDescription: String
        public let sourceText: String

        enum CodingKeys: String, CodingKey {
            case profileName = "profile_name"
            case createdAt = "created_at"
            case voiceDescription = "voice_description"
            case sourceText = "source_text"
        }

        public init(
            profileName: String,
            createdAt: Date,
            voiceDescription: String,
            sourceText: String
        ) {
            self.profileName = profileName
            self.createdAt = createdAt
            self.voiceDescription = voiceDescription
            self.sourceText = sourceText
        }
    }
}

struct StoredProfile: Sendable, Equatable {
    let manifest: ProfileManifest
    let directoryURL: URL
    let referenceAudioURL: URL
}

// MARK: - Profile Store

struct ProfileStore {
    static let directoryName = "SpeakSwiftly"
    static let profilesDirectoryName = "profiles"
    static let textProfilesFileName = "text-profiles.json"
    static let manifestFileName = "profile.json"
    static let audioFileName = "reference.wav"

    let rootURL: URL
    let fileManager: FileManager
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = ProfileStore.makeEncoder(),
        decoder: JSONDecoder = ProfileStore.makeDecoder()
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    func ensureRootExists() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func validateProfileName(_ profileName: String) throws {
        let regex = try NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9._-]{0,63}$"#)
        let range = NSRange(location: 0, length: profileName.utf16.count)

        guard regex.firstMatch(in: profileName, options: [], range: range) != nil else {
            throw WorkerError(
                code: .invalidProfileName,
                message: "Profile name '\(profileName)' is invalid. Use 1 to 64 lowercase ASCII characters from a-z, 0-9, '.', '_' or '-'."
            )
        }
    }

    func createProfile(
        profileName: String,
        modelRepo: String,
        voiceDescription: String,
        sourceText: String,
        sampleRate: Int,
        canonicalAudioData: Data
    ) throws -> StoredProfile {
        try ensureRootExists()
        try validateProfileName(profileName)

        let directoryURL = profileDirectoryURL(for: profileName)
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .profileAlreadyExists,
                message: "Profile '\(profileName)' already exists in the SpeakSwiftly profile store and cannot be overwritten."
            )
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let manifest = ProfileManifest(
            version: 1,
            profileName: profileName,
            createdAt: Date(),
            modelRepo: modelRepo,
            voiceDescription: voiceDescription,
            sourceText: sourceText,
            referenceAudioFile: Self.audioFileName,
            sampleRate: sampleRate
        )

        do {
            try canonicalAudioData.write(to: referenceAudioURL(for: directoryURL), options: .atomic)
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestURL(for: directoryURL), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw WorkerError(code: .filesystemError, message: "Profile '\(profileName)' could not be written to disk. \(error.localizedDescription)")
        }

        return StoredProfile(
            manifest: manifest,
            directoryURL: directoryURL,
            referenceAudioURL: referenceAudioURL(for: directoryURL)
        )
    }

    func loadProfile(named profileName: String) throws -> StoredProfile {
        try ensureRootExists()
        try validateProfileName(profileName)

        let directoryURL = profileDirectoryURL(for: profileName)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .profileNotFound,
                message: "Profile '\(profileName)' was not found in the SpeakSwiftly profile store."
            )
        }

        do {
            let manifestData = try Data(contentsOf: manifestURL(for: directoryURL))
            let manifest = try decoder.decode(ProfileManifest.self, from: manifestData)
            return StoredProfile(
                manifest: manifest,
                directoryURL: directoryURL,
                referenceAudioURL: referenceAudioURL(for: directoryURL, fileName: manifest.referenceAudioFile)
            )
        } catch let workerError as WorkerError {
            throw workerError
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' exists, but its metadata could not be read. \(error.localizedDescription)"
            )
        }
    }

    func listProfiles() throws -> [ProfileSummary] {
        try ensureRootExists()

        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let manifests = try urls
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .map { directoryURL in
                do {
                    let manifestPath = manifestURL(for: directoryURL)
                    let manifestData = try Data(contentsOf: manifestPath)
                    return try decoder.decode(ProfileManifest.self, from: manifestData)
                } catch {
                    throw WorkerError(
                        code: .filesystemError,
                        message: "SpeakSwiftly could not list stored profiles because the manifest in '\(directoryURL.path)' is unreadable or corrupt. \(error.localizedDescription)"
                    )
                }
            }

        return manifests.map {
            ProfileSummary(
                profileName: $0.profileName,
                createdAt: $0.createdAt,
                voiceDescription: $0.voiceDescription,
                sourceText: $0.sourceText
            )
        }
    }

    func removeProfile(named profileName: String) throws {
        try ensureRootExists()
        try validateProfileName(profileName)

        let directoryURL = profileDirectoryURL(for: profileName)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .profileNotFound,
                message: "Profile '\(profileName)' was not found in the SpeakSwiftly profile store."
            )
        }

        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' could not be removed from disk. \(error.localizedDescription)"
            )
        }
    }

    func exportCanonicalAudio(for profile: StoredProfile, to outputPath: String) throws {
        let outputURL = resolveOutputURL(outputPath)
        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw WorkerError(
                code: .filesystemError,
                message: "The export path '\(outputURL.path)' already exists. SpeakSwiftly does not overwrite existing files."
            )
        }

        do {
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: profile.referenceAudioURL, to: outputURL)
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profile.manifest.profileName)' could not be exported to '\(outputURL.path)'. \(error.localizedDescription)"
            )
        }
    }

    func resolveOutputURL(_ outputPath: String) -> URL {
        let url = URL(fileURLWithPath: outputPath)
        if url.isFileURL, outputPath.hasPrefix("/") {
            return url
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent(outputPath)
    }

    func profileDirectoryURL(for profileName: String) -> URL {
        rootURL.appendingPathComponent(profileName, isDirectory: true)
    }

    func manifestURL(for directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(Self.manifestFileName)
    }

    func referenceAudioURL(for directoryURL: URL, fileName: String = Self.audioFileName) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static func defaultRootURL(fileManager: FileManager = .default, overridePath: String? = nil) -> URL {
        if let overridePath, !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }

        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(profilesDirectoryName, isDirectory: true)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
