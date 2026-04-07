import Foundation

// MARK: - Voice & Clone Profile Models

enum ProfileSourceKind: String, Codable, Sendable, Equatable {
    case generated
    case importedClone = "imported_clone"
}

struct ProfileMaterializationManifest: Codable, Sendable, Equatable {
    let backend: SpeakSwiftly.SpeechBackend
    let modelRepo: String
    let createdAt: Date
    let referenceAudioFile: String
    let referenceText: String
    let sampleRate: Int
}

struct ProfileManifest: Codable, Sendable, Equatable {
    let version: Int
    let profileName: String
    let vibe: SpeakSwiftly.Vibe
    let createdAt: Date
    let sourceKind: ProfileSourceKind
    let modelRepo: String
    let voiceDescription: String
    let sourceText: String
    let sampleRate: Int
    let backendMaterializations: [ProfileMaterializationManifest]
}

private struct LegacyProfileManifest: Codable, Sendable, Equatable {
    let version: Int
    let profileName: String
    let createdAt: Date
    let modelRepo: String
    let voiceDescription: String
    let sourceText: String
    let referenceAudioFile: String
    let sampleRate: Int
}

private struct LegacyMultiBackendProfileManifest: Codable, Sendable, Equatable {
    let version: Int
    let profileName: String
    let createdAt: Date
    let sourceKind: ProfileSourceKind
    let modelRepo: String
    let voiceDescription: String
    let sourceText: String
    let sampleRate: Int
    let backendMaterializations: [ProfileMaterializationManifest]
}

public extension SpeakSwiftly {
    struct ProfileSummary: Codable, Sendable, Equatable {
        public let profileName: String
        public let vibe: SpeakSwiftly.Vibe
        public let createdAt: Date
        public let voiceDescription: String
        public let sourceText: String

        enum CodingKeys: String, CodingKey {
            case profileName = "profile_name"
            case vibe
            case createdAt = "created_at"
            case voiceDescription = "voice_description"
            case sourceText = "source_text"
        }

        public init(
            profileName: String,
            vibe: SpeakSwiftly.Vibe,
            createdAt: Date,
            voiceDescription: String,
            sourceText: String
        ) {
            self.profileName = profileName
            self.vibe = vibe
            self.createdAt = createdAt
            self.voiceDescription = voiceDescription
            self.sourceText = sourceText
        }
    }
}

struct ProfileMaterializationDraft: Sendable, Equatable {
    let backend: SpeakSwiftly.SpeechBackend
    let modelRepo: String
    let referenceAudioFile: String
    let referenceText: String
    let sampleRate: Int
    let audioData: Data
}

struct StoredProfileMaterialization: Sendable, Equatable {
    let manifest: ProfileMaterializationManifest
    let referenceAudioURL: URL
}

struct StoredProfile: Sendable, Equatable {
    let manifest: ProfileManifest
    let directoryURL: URL
    let materializations: [StoredProfileMaterialization]

    var referenceAudioURL: URL {
        try! qwenMaterialization().referenceAudioURL
    }

    func qwenMaterialization() throws -> StoredProfileMaterialization {
        if let materialization = materializations.first(where: { $0.manifest.backend == .qwen3 }) {
            return materialization
        }

        throw WorkerError(
            code: .profileNotFound,
            message: "Profile '\(manifest.profileName)' does not contain a stored 'qwen3' materialization. Recreate the profile to prepare Qwen assets for that profile."
        )
    }
}

// MARK: - Profile Store

struct ProfileStore: @unchecked Sendable {
    static let directoryName = "SpeakSwiftly"
    static let profilesDirectoryName = "profiles"
    static let textProfilesFileName = "text-profiles.json"
    static let configurationFileName = "configuration.json"
    static let manifestFileName = "profile.json"
    static let audioFileName = "reference.wav"
    static let manifestVersion = 3

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
        vibe: SpeakSwiftly.Vibe,
        modelRepo: String,
        voiceDescription: String,
        sourceText: String,
        sampleRate: Int,
        canonicalAudioData: Data
    ) throws -> StoredProfile {
        let sourceKind: ProfileSourceKind = modelRepo == ModelFactory.importedCloneModelRepo ? .importedClone : .generated
        let materializations = [
            ProfileMaterializationDraft(
                backend: .qwen3,
                modelRepo: ModelFactory.residentModelRepo(for: .qwen3),
                referenceAudioFile: Self.audioFileName,
                referenceText: sourceText,
                sampleRate: sampleRate,
                audioData: canonicalAudioData
            ),
        ]

        return try createProfile(
            profileName: profileName,
            vibe: vibe,
            sourceKind: sourceKind,
            sourceModelRepo: modelRepo,
            voiceDescription: voiceDescription,
            sourceText: sourceText,
            sampleRate: sampleRate,
            materializations: materializations
        )
    }

    func createProfile(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        sourceKind: ProfileSourceKind,
        sourceModelRepo: String,
        voiceDescription: String,
        sourceText: String,
        sampleRate: Int,
        materializations: [ProfileMaterializationDraft]
    ) throws -> StoredProfile {
        try ensureRootExists()
        try validateProfileName(profileName)

        guard !materializations.isEmpty else {
            throw WorkerError(
                code: .internalError,
                message: "Profile '\(profileName)' could not be created because no backend materializations were supplied. This indicates a SpeakSwiftly runtime bug."
            )
        }

        let directoryURL = profileDirectoryURL(for: profileName)
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .profileAlreadyExists,
                message: "Profile '\(profileName)' already exists in the SpeakSwiftly profile store and cannot be overwritten."
            )
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let createdAt = Date()
        let manifest = ProfileManifest(
            version: Self.manifestVersion,
            profileName: profileName,
            vibe: vibe,
            createdAt: createdAt,
            sourceKind: sourceKind,
            modelRepo: sourceModelRepo,
            voiceDescription: voiceDescription,
            sourceText: sourceText,
            sampleRate: sampleRate,
            backendMaterializations: materializations.map {
                ProfileMaterializationManifest(
                    backend: $0.backend,
                    modelRepo: $0.modelRepo,
                    createdAt: createdAt,
                    referenceAudioFile: $0.referenceAudioFile,
                    referenceText: $0.referenceText,
                    sampleRate: $0.sampleRate
                )
            }
        )

        do {
            try writeMaterializationFiles(materializations, to: directoryURL)
            try writeManifest(manifest, to: directoryURL)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' could not be written to disk. \(error.localizedDescription)"
            )
        }

        return try loadProfile(named: profileName)
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
            let manifest = try loadManifest(from: directoryURL)
            let materializations = manifest.backendMaterializations.map {
                StoredProfileMaterialization(
                    manifest: $0,
                    referenceAudioURL: referenceAudioURL(for: directoryURL, fileName: $0.referenceAudioFile)
                )
            }
            return StoredProfile(
                manifest: manifest,
                directoryURL: directoryURL,
                materializations: materializations
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
            .compactMap { directoryURL -> ProfileManifest? in
                guard try isDirectory(directoryURL) else {
                    return nil
                }

                let manifestPath = manifestURL(for: directoryURL)
                guard fileManager.fileExists(atPath: manifestPath.path) else {
                    return nil
                }

                return try? loadManifest(from: directoryURL)
            }

        return manifests.map {
            ProfileSummary(
                profileName: $0.profileName,
                vibe: $0.vibe,
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
        defaultBaseURL(fileManager: fileManager, profileRootOverride: overridePath)
            .appendingPathComponent(profilesDirectoryName, isDirectory: true)
    }

    static func defaultConfigurationURL(
        fileManager: FileManager = .default,
        profileRootOverride: String? = nil
    ) -> URL {
        defaultBaseURL(fileManager: fileManager, profileRootOverride: profileRootOverride)
            .appendingPathComponent(configurationFileName, isDirectory: false)
    }

    private static func defaultBaseURL(
        fileManager: FileManager = .default,
        profileRootOverride: String? = nil
    ) -> URL {
        if let profileRootOverride, !profileRootOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: profileRootOverride, isDirectory: true)
                .deletingLastPathComponent()
        }

        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private func loadManifest(from directoryURL: URL) throws -> ProfileManifest {
        let manifestPath = manifestURL(for: directoryURL)
        let manifestData = try Data(contentsOf: manifestPath)

        if let manifest = try? decoder.decode(ProfileManifest.self, from: manifestData) {
            return manifest
        }

        if let legacyManifest = try? decoder.decode(LegacyMultiBackendProfileManifest.self, from: manifestData) {
            let upgradedManifest = upgradeLegacyMultiBackendManifest(legacyManifest)
            try writeManifest(upgradedManifest, to: directoryURL)
            return upgradedManifest
        }

        if let legacyManifest = try? decoder.decode(LegacyProfileManifest.self, from: manifestData) {
            let upgradedManifest = upgradeLegacyManifest(legacyManifest)
            try writeManifest(upgradedManifest, to: directoryURL)
            return upgradedManifest
        }

        throw WorkerError(
            code: .filesystemError,
            message: "SpeakSwiftly could not read the profile manifest at '\(manifestPath.path)' because the file is unreadable or corrupt."
        )
    }

    private func upgradeLegacyManifest(_ legacyManifest: LegacyProfileManifest) -> ProfileManifest {
        let sourceKind: ProfileSourceKind = legacyManifest.modelRepo == ModelFactory.importedCloneModelRepo ? .importedClone : .generated
        let materializations = [
            ProfileMaterializationManifest(
                backend: .qwen3,
                modelRepo: ModelFactory.residentModelRepo(for: .qwen3),
                createdAt: legacyManifest.createdAt,
                referenceAudioFile: legacyManifest.referenceAudioFile,
                referenceText: legacyManifest.sourceText,
                sampleRate: legacyManifest.sampleRate
            ),
        ]

        return ProfileManifest(
            version: Self.manifestVersion,
            profileName: legacyManifest.profileName,
            vibe: inferredLegacyVibe(
                profileName: legacyManifest.profileName,
                voiceDescription: legacyManifest.voiceDescription
            ),
            createdAt: legacyManifest.createdAt,
            sourceKind: sourceKind,
            modelRepo: legacyManifest.modelRepo,
            voiceDescription: legacyManifest.voiceDescription,
            sourceText: legacyManifest.sourceText,
            sampleRate: legacyManifest.sampleRate,
            backendMaterializations: materializations
        )
    }

    private func upgradeLegacyMultiBackendManifest(_ legacyManifest: LegacyMultiBackendProfileManifest) -> ProfileManifest {
        let qwenMaterializations = legacyManifest.backendMaterializations.filter { $0.backend == .qwen3 }
        let materializations = if qwenMaterializations.isEmpty {
            [
                ProfileMaterializationManifest(
                    backend: .qwen3,
                    modelRepo: ModelFactory.residentModelRepo(for: .qwen3),
                    createdAt: legacyManifest.createdAt,
                    referenceAudioFile: Self.audioFileName,
                    referenceText: legacyManifest.sourceText,
                    sampleRate: legacyManifest.sampleRate
                ),
            ]
        } else {
            qwenMaterializations
        }

        return ProfileManifest(
            version: Self.manifestVersion,
            profileName: legacyManifest.profileName,
            vibe: inferredLegacyVibe(
                profileName: legacyManifest.profileName,
                voiceDescription: legacyManifest.voiceDescription
            ),
            createdAt: legacyManifest.createdAt,
            sourceKind: legacyManifest.sourceKind,
            modelRepo: legacyManifest.modelRepo,
            voiceDescription: legacyManifest.voiceDescription,
            sourceText: legacyManifest.sourceText,
            sampleRate: legacyManifest.sampleRate,
            backendMaterializations: materializations
        )
    }

    private func inferredLegacyVibe(
        profileName: String,
        voiceDescription: String
    ) -> SpeakSwiftly.Vibe {
        let signal = "\(profileName) \(voiceDescription)".lowercased()

        if signal.contains("femme")
            || signal.contains("female")
            || signal.contains("feminine")
            || signal.contains("woman")
            || signal.contains("girl")
        {
            return .femme
        }

        if signal.contains("masc")
            || signal.contains("male")
            || signal.contains("masculine")
            || signal.contains("man")
            || signal.contains("boy")
        {
            return .masc
        }

        return .androgenous
    }

    private func writeMaterializationFiles(
        _ materializations: [ProfileMaterializationDraft],
        to directoryURL: URL
    ) throws {
        var writtenFiles = Set<String>()

        for materialization in materializations {
            if writtenFiles.contains(materialization.referenceAudioFile) {
                continue
            }

            try materialization.audioData.write(
                to: referenceAudioURL(for: directoryURL, fileName: materialization.referenceAudioFile),
                options: .atomic
            )
            writtenFiles.insert(materialization.referenceAudioFile)
        }
    }

    private func writeManifest(_ manifest: ProfileManifest, to directoryURL: URL) throws {
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL(for: directoryURL), options: .atomic)
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
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
