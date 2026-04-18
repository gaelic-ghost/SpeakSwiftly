import Foundation
import MLXAudioTTS

// MARK: - ProfileStore

struct ProfileStore: @unchecked Sendable {
    static let directoryName = "SpeakSwiftly"
    static let profilesDirectoryName = "profiles"
    static let textProfilesFileName = "text-profiles.json"
    static let configurationFileName = "configuration.json"
    static let manifestFileName = "profile.json"
    static let audioFileName = "reference.wav"
    static let manifestVersion = 5

    private static var defaultDirectoryName: String {
#if DEBUG
        return "\(directoryName)-Debug"
#else
        return directoryName
#endif
    }

    let rootURL: URL
    let fileManager: FileManager
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = ProfileStore.makeEncoder(),
        decoder: JSONDecoder = ProfileStore.makeDecoder(),
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    static func defaultRootURL(fileManager: FileManager = .default, overridePath: String? = nil) -> URL {
        defaultBaseURL(fileManager: fileManager, profileRootOverride: overridePath)
            .appendingPathComponent(profilesDirectoryName, isDirectory: true)
    }

    static func defaultConfigurationURL(
        fileManager: FileManager = .default,
        profileRootOverride: String? = nil,
    ) -> URL {
        defaultBaseURL(fileManager: fileManager, profileRootOverride: profileRootOverride)
            .appendingPathComponent(configurationFileName, isDirectory: false)
    }

    static func defaultTextProfilesURL(
        fileManager: FileManager = .default,
        profileRootOverride: String? = nil,
    ) -> URL {
        defaultBaseURL(fileManager: fileManager, profileRootOverride: profileRootOverride)
            .appendingPathComponent(textProfilesFileName, isDirectory: false)
    }

    private static func defaultBaseURL(
        fileManager: FileManager = .default,
        profileRootOverride: String? = nil,
    ) -> URL {
        if let profileRootOverride, !profileRootOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedOverrideBaseURL(profileRootOverride)
        }

        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(defaultDirectoryName, isDirectory: true)
    }

    private static func normalizedOverrideBaseURL(_ profileRootOverride: String) -> URL {
        let overrideURL = URL(fileURLWithPath: profileRootOverride, isDirectory: true)
            .standardizedFileURL

        if overrideURL.lastPathComponent == profilesDirectoryName {
            return overrideURL.deletingLastPathComponent()
        }

        return overrideURL
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

    private static func qwenConditioningArtifactFileName(
        for backend: SpeakSwiftly.SpeechBackend,
    ) -> String {
        "qwen-conditioning-\(backend.rawValue).json"
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
                message: "Profile name '\(profileName)' is invalid. Use 1 to 64 lowercase ASCII characters from a-z, 0-9, '.', '_' or '-'.",
            )
        }
    }

    func createProfile(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        modelRepo: String,
        voiceDescription: String,
        sourceText: String,
        transcriptProvenance: TranscriptProvenance? = nil,
        sampleRate: Int,
        canonicalAudioData: Data,
    ) throws -> StoredProfile {
        let sourceKind: ProfileSourceKind = modelRepo == ModelFactory.importedCloneModelRepo ? .importedClone : .generated
        let materializations = [
            ProfileMaterializationDraft(
                backend: .qwen3,
                modelRepo: ModelFactory.residentModelRepo(for: .qwen3),
                referenceAudioFile: Self.audioFileName,
                referenceText: sourceText,
                sampleRate: sampleRate,
                audioData: canonicalAudioData,
            ),
        ]

        return try createProfile(
            profileName: profileName,
            vibe: vibe,
            sourceKind: sourceKind,
            sourceModelRepo: modelRepo,
            voiceDescription: voiceDescription,
            sourceText: sourceText,
            transcriptProvenance: transcriptProvenance,
            sampleRate: sampleRate,
            materializations: materializations,
        )
    }

    func createProfile(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        sourceKind: ProfileSourceKind,
        sourceModelRepo: String,
        voiceDescription: String,
        sourceText: String,
        transcriptProvenance: TranscriptProvenance? = nil,
        sampleRate: Int,
        materializations: [ProfileMaterializationDraft],
    ) throws -> StoredProfile {
        try ensureRootExists()
        try validateProfileName(profileName)

        guard !materializations.isEmpty else {
            throw WorkerError(
                code: .internalError,
                message: "Profile '\(profileName)' could not be created because no backend materializations were supplied. This indicates a SpeakSwiftly runtime bug.",
            )
        }

        let directoryURL = profileDirectoryURL(for: profileName)
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .profileAlreadyExists,
                message: "Profile '\(profileName)' already exists in the SpeakSwiftly profile store and cannot be overwritten.",
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
            transcriptProvenance: transcriptProvenance,
            sampleRate: sampleRate,
            backendMaterializations: materializations.map {
                ProfileMaterializationManifest(
                    backend: $0.backend,
                    modelRepo: $0.modelRepo,
                    createdAt: createdAt,
                    referenceAudioFile: $0.referenceAudioFile,
                    referenceText: $0.referenceText,
                    sampleRate: $0.sampleRate,
                )
            },
            qwenConditioningArtifacts: [],
        )

        do {
            try writeMaterializationFiles(materializations, to: directoryURL)
            try writeManifest(manifest, to: directoryURL)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' could not be written to disk. \(error.localizedDescription)",
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
                message: "Profile '\(profileName)' was not found in the SpeakSwiftly profile store.",
            )
        }

        do {
            let manifest = try loadManifest(from: directoryURL)
            let materializations = manifest.backendMaterializations.map {
                StoredProfileMaterialization(
                    manifest: $0,
                    referenceAudioURL: referenceAudioURL(for: directoryURL, fileName: $0.referenceAudioFile),
                )
            }
            let conditioningArtifacts = manifest.qwenConditioningArtifacts.map {
                StoredQwenConditioningArtifact(
                    manifest: $0,
                    artifactURL: qwenConditioningArtifactURL(for: directoryURL, fileName: $0.artifactFile),
                )
            }
            return StoredProfile(
                manifest: manifest,
                directoryURL: directoryURL,
                materializations: materializations,
                conditioningArtifacts: conditioningArtifacts,
            )
        } catch let workerError as WorkerError {
            throw workerError
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' exists, but its metadata could not be read. \(error.localizedDescription)",
            )
        }
    }

    func listProfiles() throws -> [ProfileSummary] {
        try ensureRootExists()

        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
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
                sourceText: $0.sourceText,
                transcriptSource: $0.transcriptProvenance.map {
                    switch $0.source {
                        case .provided:
                            .provided
                        case .inferred:
                            .inferred
                    }
                },
                transcriptResolvedAt: $0.transcriptProvenance?.createdAt,
                transcriptionModelRepo: $0.transcriptProvenance?.transcriptionModelRepo,
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
                message: "Profile '\(profileName)' was not found in the SpeakSwiftly profile store.",
            )
        }

        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' could not be removed from disk. \(error.localizedDescription)",
            )
        }
    }

    func renameProfile(
        named profileName: String,
        to newProfileName: String,
    ) throws -> StoredProfile {
        try ensureRootExists()
        try validateProfileName(profileName)
        try validateProfileName(newProfileName)

        guard profileName != newProfileName else {
            throw WorkerError(
                code: .invalidProfileName,
                message: "Profile '\(profileName)' is already named '\(newProfileName)'. Choose a different target name before requesting a rename.",
            )
        }

        let directoryURL = profileDirectoryURL(for: profileName)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .profileNotFound,
                message: "Profile '\(profileName)' was not found in the SpeakSwiftly profile store.",
            )
        }

        let newDirectoryURL = profileDirectoryURL(for: newProfileName)
        guard !fileManager.fileExists(atPath: newDirectoryURL.path) else {
            throw WorkerError(
                code: .profileAlreadyExists,
                message: "Profile '\(newProfileName)' already exists in the SpeakSwiftly profile store and cannot be replaced by renaming '\(profileName)'.",
            )
        }

        let storedProfile = try loadProfile(named: profileName)
        let renamedManifest = ProfileManifest(
            version: storedProfile.manifest.version,
            profileName: newProfileName,
            vibe: storedProfile.manifest.vibe,
            createdAt: storedProfile.manifest.createdAt,
            sourceKind: storedProfile.manifest.sourceKind,
            modelRepo: storedProfile.manifest.modelRepo,
            voiceDescription: storedProfile.manifest.voiceDescription,
            sourceText: storedProfile.manifest.sourceText,
            transcriptProvenance: storedProfile.manifest.transcriptProvenance,
            sampleRate: storedProfile.manifest.sampleRate,
            backendMaterializations: storedProfile.manifest.backendMaterializations,
            qwenConditioningArtifacts: storedProfile.manifest.qwenConditioningArtifacts,
        )

        do {
            try fileManager.moveItem(at: directoryURL, to: newDirectoryURL)
            do {
                try writeManifest(renamedManifest, to: newDirectoryURL)
            } catch let manifestWriteError {
                do {
                    try fileManager.moveItem(at: newDirectoryURL, to: directoryURL)
                } catch let rollbackError {
                    throw WorkerError(
                        code: .filesystemError,
                        message: "Profile '\(profileName)' was moved to '\(newProfileName)', but SpeakSwiftly could not restore the original directory after the manifest rewrite failed. Manifest error: \(manifestWriteError.localizedDescription) Rollback error: \(rollbackError.localizedDescription)",
                    )
                }

                throw manifestWriteError
            }
        } catch let workerError as WorkerError {
            throw workerError
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' could not be renamed to '\(newProfileName)'. \(error.localizedDescription)",
            )
        }

        return try loadProfile(named: newProfileName)
    }

    func replaceProfile(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        modelRepo: String,
        voiceDescription: String,
        sourceText: String,
        transcriptProvenance: TranscriptProvenance? = nil,
        sampleRate: Int,
        canonicalAudioData: Data,
        createdAt: Date,
    ) throws -> StoredProfile {
        let sourceKind: ProfileSourceKind = modelRepo == ModelFactory.importedCloneModelRepo ? .importedClone : .generated
        let materializations = [
            ProfileMaterializationDraft(
                backend: .qwen3,
                modelRepo: ModelFactory.residentModelRepo(for: .qwen3),
                referenceAudioFile: Self.audioFileName,
                referenceText: sourceText,
                sampleRate: sampleRate,
                audioData: canonicalAudioData,
            ),
        ]

        return try replaceProfile(
            named: profileName,
            vibe: vibe,
            sourceKind: sourceKind,
            sourceModelRepo: modelRepo,
            voiceDescription: voiceDescription,
            sourceText: sourceText,
            transcriptProvenance: transcriptProvenance,
            sampleRate: sampleRate,
            materializations: materializations,
            createdAt: createdAt,
        )
    }

    func replaceProfile(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        sourceKind: ProfileSourceKind,
        sourceModelRepo: String,
        voiceDescription: String,
        sourceText: String,
        transcriptProvenance: TranscriptProvenance? = nil,
        sampleRate: Int,
        materializations: [ProfileMaterializationDraft],
        createdAt: Date,
    ) throws -> StoredProfile {
        try ensureRootExists()
        try validateProfileName(profileName)

        guard !materializations.isEmpty else {
            throw WorkerError(
                code: .internalError,
                message: "Profile '\(profileName)' could not be replaced because no backend materializations were supplied. This indicates a SpeakSwiftly runtime bug.",
            )
        }

        let directoryURL = profileDirectoryURL(for: profileName)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            throw WorkerError(
                code: .profileNotFound,
                message: "Profile '\(profileName)' was not found in the SpeakSwiftly profile store.",
            )
        }

        let stagedDirectoryURL = rootURL.appendingPathComponent(".\(profileName).stage-\(UUID().uuidString)", isDirectory: true)
        let backupDirectoryURL = rootURL.appendingPathComponent(".\(profileName).backup-\(UUID().uuidString)", isDirectory: true)
        let manifest = ProfileManifest(
            version: Self.manifestVersion,
            profileName: profileName,
            vibe: vibe,
            createdAt: createdAt,
            sourceKind: sourceKind,
            modelRepo: sourceModelRepo,
            voiceDescription: voiceDescription,
            sourceText: sourceText,
            transcriptProvenance: transcriptProvenance,
            sampleRate: sampleRate,
            backendMaterializations: materializations.map {
                ProfileMaterializationManifest(
                    backend: $0.backend,
                    modelRepo: $0.modelRepo,
                    createdAt: createdAt,
                    referenceAudioFile: $0.referenceAudioFile,
                    referenceText: $0.referenceText,
                    sampleRate: $0.sampleRate,
                )
            },
            qwenConditioningArtifacts: [],
        )

        do {
            try fileManager.createDirectory(at: stagedDirectoryURL, withIntermediateDirectories: false)
            try writeMaterializationFiles(materializations, to: stagedDirectoryURL)
            try writeManifest(manifest, to: stagedDirectoryURL)
            try fileManager.moveItem(at: directoryURL, to: backupDirectoryURL)

            do {
                try fileManager.moveItem(at: stagedDirectoryURL, to: directoryURL)
            } catch let moveInError {
                try? fileManager.moveItem(at: backupDirectoryURL, to: directoryURL)
                throw WorkerError(
                    code: .filesystemError,
                    message: "Profile '\(profileName)' could not be replaced with the rerolled assets after staging succeeded. \(moveInError.localizedDescription)",
                )
            }

            try fileManager.removeItem(at: backupDirectoryURL)
        } catch let workerError as WorkerError {
            try? fileManager.removeItem(at: stagedDirectoryURL)
            throw workerError
        } catch {
            try? fileManager.removeItem(at: stagedDirectoryURL)
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' could not be replaced in place. \(error.localizedDescription)",
            )
        }

        return try loadProfile(named: profileName)
    }

    func exportCanonicalAudio(for profile: StoredProfile, to outputURL: URL) throws {
        guard !fileManager.fileExists(atPath: outputURL.path) else {
            throw WorkerError(
                code: .filesystemError,
                message: "The export path '\(outputURL.path)' already exists. SpeakSwiftly does not overwrite existing files.",
            )
        }

        do {
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: profile.referenceAudioURL, to: outputURL)
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profile.manifest.profileName)' could not be exported to '\(outputURL.path)'. \(error.localizedDescription)",
            )
        }
    }

    func storeQwenConditioningArtifact(
        named profileName: String,
        backend: SpeakSwiftly.SpeechBackend,
        modelRepo: String,
        conditioning: Qwen3TTSModel.Qwen3TTSReferenceConditioning,
        createdAt: Date = Date(),
    ) throws -> StoredProfile {
        let storedProfile = try loadProfile(named: profileName)
        let artifactFile = Self.qwenConditioningArtifactFileName(for: backend)
        let persistedArtifact = PersistedQwenConditioningArtifact(conditioning: conditioning)
        let updatedArtifactManifest = QwenConditioningArtifactManifest(
            backend: backend,
            modelRepo: modelRepo,
            createdAt: createdAt,
            artifactVersion: PersistedQwenConditioningArtifact.currentVersion,
            artifactFile: artifactFile,
        )
        let updatedArtifacts = (
            storedProfile.manifest.qwenConditioningArtifacts.filter { $0.backend != backend } + [updatedArtifactManifest],
        )
        .sorted { $0.backend.rawValue < $1.backend.rawValue }
        let updatedManifest = ProfileManifest(
            version: Self.manifestVersion,
            profileName: storedProfile.manifest.profileName,
            vibe: storedProfile.manifest.vibe,
            createdAt: storedProfile.manifest.createdAt,
            sourceKind: storedProfile.manifest.sourceKind,
            modelRepo: storedProfile.manifest.modelRepo,
            voiceDescription: storedProfile.manifest.voiceDescription,
            sourceText: storedProfile.manifest.sourceText,
            transcriptProvenance: storedProfile.manifest.transcriptProvenance,
            sampleRate: storedProfile.manifest.sampleRate,
            backendMaterializations: storedProfile.manifest.backendMaterializations,
            qwenConditioningArtifacts: updatedArtifacts,
        )

        do {
            try writeQwenConditioningArtifact(
                persistedArtifact,
                to: storedProfile.directoryURL,
                fileName: artifactFile,
            )
            try writeManifest(updatedManifest, to: storedProfile.directoryURL)
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "Profile '\(profileName)' could not persist the prepared Qwen conditioning artifact for the '\(backend.rawValue)' backend. \(error.localizedDescription)",
            )
        }

        return try loadProfile(named: profileName)
    }

    func loadQwenConditioningArtifact(
        _ storedArtifact: StoredQwenConditioningArtifact,
    ) throws -> Qwen3TTSModel.Qwen3TTSReferenceConditioning {
        do {
            let data = try Data(contentsOf: storedArtifact.artifactURL)
            let artifact = try decoder.decode(PersistedQwenConditioningArtifact.self, from: data)
            guard artifact.version == PersistedQwenConditioningArtifact.currentVersion else {
                throw WorkerError(
                    code: .filesystemError,
                    message: "SpeakSwiftly found a prepared Qwen conditioning artifact at '\(storedArtifact.artifactURL.path)', but the artifact version '\(artifact.version)' is not supported by this runtime. Recreate or reroll the profile to rebuild the artifact.",
                )
            }

            return artifact.makeConditioning()
        } catch let workerError as WorkerError {
            throw workerError
        } catch {
            throw WorkerError(
                code: .filesystemError,
                message: "SpeakSwiftly could not load the prepared Qwen conditioning artifact at '\(storedArtifact.artifactURL.path)' for the '\(storedArtifact.manifest.backend.rawValue)' backend. \(error.localizedDescription)",
            )
        }
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

    func qwenConditioningArtifactURL(
        for directoryURL: URL,
        fileName: String,
    ) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }
}
