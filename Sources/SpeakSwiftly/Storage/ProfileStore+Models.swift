import Foundation

enum ProfileSourceKind: String, Codable, Equatable {
    case generated
    case importedClone = "imported_clone"
}

public extension SpeakSwiftly {
    enum ProfileAuthor: String, Codable, Sendable, Equatable {
        case user
        case system
    }

    struct ProfileSeed: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case seedID
            case seedVersion
            case intendedProfileName
            case fallbackProfileName
            case installedAt
            case sourcePackage
            case sourceVersion
            case sampleMediaPath
        }

        public let seedID: String
        public let seedVersion: String
        public let intendedProfileName: String
        public let fallbackProfileName: String?
        public let installedAt: Date
        public let sourcePackage: String
        public let sourceVersion: String?
        public let sampleMediaPath: String?

        public init(
            seedID: String,
            seedVersion: String,
            intendedProfileName: String,
            fallbackProfileName: String? = nil,
            installedAt: Date = Date(),
            sourcePackage: String,
            sourceVersion: String? = nil,
            sampleMediaPath: String? = nil,
        ) {
            self.seedID = seedID
            self.seedVersion = seedVersion
            self.intendedProfileName = intendedProfileName
            self.fallbackProfileName = fallbackProfileName
            self.installedAt = installedAt
            self.sourcePackage = sourcePackage
            self.sourceVersion = sourceVersion
            self.sampleMediaPath = sampleMediaPath
        }
    }
}

struct TranscriptProvenance: Codable, Equatable {
    enum Source: String, Codable, Equatable {
        case provided
        case inferred
    }

    let source: Source
    let createdAt: Date
    let transcriptionModelRepo: String?
}

struct ProfileMaterializationManifest: Codable, Equatable {
    let backend: SpeakSwiftly.SpeechBackend
    let modelRepo: String
    let createdAt: Date
    let referenceAudioFile: String
    let referenceText: String
    let sampleRate: Int
}

struct ProfileManifest: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case version
        case profileName
        case vibe
        case createdAt
        case sourceKind
        case modelRepo
        case voiceDescription
        case sourceText
        case transcriptProvenance
        case author
        case seed
        case sampleRate
        case backendMaterializations
        case qwenConditioningArtifacts
    }

    let version: Int
    let profileName: String
    let vibe: SpeakSwiftly.Vibe
    let createdAt: Date
    let sourceKind: ProfileSourceKind
    let modelRepo: String
    let voiceDescription: String
    let sourceText: String
    let transcriptProvenance: TranscriptProvenance?
    let author: SpeakSwiftly.ProfileAuthor
    let seed: SpeakSwiftly.ProfileSeed?
    let sampleRate: Int
    let backendMaterializations: [ProfileMaterializationManifest]
    let qwenConditioningArtifacts: [QwenConditioningArtifactManifest]

    init(
        version: Int,
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        createdAt: Date,
        sourceKind: ProfileSourceKind,
        modelRepo: String,
        voiceDescription: String,
        sourceText: String,
        transcriptProvenance: TranscriptProvenance?,
        author: SpeakSwiftly.ProfileAuthor = .user,
        seed: SpeakSwiftly.ProfileSeed? = nil,
        sampleRate: Int,
        backendMaterializations: [ProfileMaterializationManifest],
        qwenConditioningArtifacts: [QwenConditioningArtifactManifest],
    ) {
        self.version = version
        self.profileName = profileName
        self.vibe = vibe
        self.createdAt = createdAt
        self.sourceKind = sourceKind
        self.modelRepo = modelRepo
        self.voiceDescription = voiceDescription
        self.sourceText = sourceText
        self.transcriptProvenance = transcriptProvenance
        self.author = author
        self.seed = seed
        self.sampleRate = sampleRate
        self.backendMaterializations = backendMaterializations
        self.qwenConditioningArtifacts = qwenConditioningArtifacts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        profileName = try container.decode(String.self, forKey: .profileName)
        vibe = try container.decode(SpeakSwiftly.Vibe.self, forKey: .vibe)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceKind = try container.decode(ProfileSourceKind.self, forKey: .sourceKind)
        modelRepo = try container.decode(String.self, forKey: .modelRepo)
        voiceDescription = try container.decode(String.self, forKey: .voiceDescription)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        transcriptProvenance = try container.decodeIfPresent(
            TranscriptProvenance.self,
            forKey: .transcriptProvenance,
        )
        author = try container.decodeIfPresent(
            SpeakSwiftly.ProfileAuthor.self,
            forKey: .author,
        ) ?? .user
        seed = try container.decodeIfPresent(SpeakSwiftly.ProfileSeed.self, forKey: .seed)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        backendMaterializations = try container.decode(
            [ProfileMaterializationManifest].self,
            forKey: .backendMaterializations,
        )
        qwenConditioningArtifacts = try container.decodeIfPresent(
            [QwenConditioningArtifactManifest].self,
            forKey: .qwenConditioningArtifacts,
        ) ?? []
    }
}

struct LegacyProfileManifest: Codable, Equatable {
    let version: Int
    let profileName: String
    let createdAt: Date
    let modelRepo: String
    let voiceDescription: String
    let sourceText: String
    let referenceAudioFile: String
    let sampleRate: Int
}

struct LegacyMultiBackendProfileManifest: Codable, Equatable {
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
    /// Summary metadata for one stored voice profile.
    struct ProfileSummary: Codable, Sendable, Equatable {
        /// Describes how a clone transcript was obtained.
        public enum TranscriptSource: String, Codable, Sendable {
            case provided
            case inferred
        }

        enum CodingKeys: String, CodingKey {
            case profileName = "profile_name"
            case vibe
            case createdAt = "created_at"
            case voiceDescription = "voice_description"
            case sourceText = "source_text"
            case transcriptSource = "transcript_source"
            case transcriptResolvedAt = "transcript_resolved_at"
            case transcriptionModelRepo = "transcription_model_repo"
            case author
            case seedID = "seed_id"
            case seedVersion = "seed_version"
        }

        public let profileName: String
        public let vibe: SpeakSwiftly.Vibe
        public let createdAt: Date
        public let voiceDescription: String
        public let sourceText: String
        public let author: SpeakSwiftly.ProfileAuthor
        public let seedID: String?
        public let seedVersion: String?
        public let transcriptSource: TranscriptSource?
        public let transcriptResolvedAt: Date?
        public let transcriptionModelRepo: String?

        public init(
            profileName: String,
            vibe: SpeakSwiftly.Vibe,
            createdAt: Date,
            voiceDescription: String,
            sourceText: String,
            author: SpeakSwiftly.ProfileAuthor = .user,
            seedID: String? = nil,
            seedVersion: String? = nil,
            transcriptSource: TranscriptSource? = nil,
            transcriptResolvedAt: Date? = nil,
            transcriptionModelRepo: String? = nil,
        ) {
            self.profileName = profileName
            self.vibe = vibe
            self.createdAt = createdAt
            self.voiceDescription = voiceDescription
            self.sourceText = sourceText
            self.author = author
            self.seedID = seedID
            self.seedVersion = seedVersion
            self.transcriptSource = transcriptSource
            self.transcriptResolvedAt = transcriptResolvedAt
            self.transcriptionModelRepo = transcriptionModelRepo
        }
    }
}

struct ProfileMaterializationDraft: Equatable {
    let backend: SpeakSwiftly.SpeechBackend
    let modelRepo: String
    let referenceAudioFile: String
    let referenceText: String
    let sampleRate: Int
    let audioData: Data
}

struct StoredProfileMaterialization: Equatable {
    let manifest: ProfileMaterializationManifest
    let referenceAudioURL: URL
}

struct StoredProfile: Equatable {
    let manifest: ProfileManifest
    let directoryURL: URL
    let materializations: [StoredProfileMaterialization]
    let conditioningArtifacts: [StoredQwenConditioningArtifact]

    var referenceAudioURL: URL {
        get throws {
            try qwenMaterialization(for: .qwen3).referenceAudioURL
        }
    }

    func qwenMaterialization(for backend: SpeakSwiftly.SpeechBackend) throws -> StoredProfileMaterialization {
        if let materialization = materializations.first(where: { $0.manifest.backend == backend }) {
            return materialization
        }

        if let materialization = materializations.first(where: { $0.manifest.backend.isQwenFamily }) {
            return materialization
        }

        throw WorkerError(
            code: .profileNotFound,
            message: "Profile '\(manifest.profileName)' does not contain a stored Qwen reference materialization for the '\(backend.rawValue)' backend. Recreate or reroll the profile to restore the canonical Qwen reference assets.",
        )
    }

    func qwenMaterialization() throws -> StoredProfileMaterialization {
        try qwenMaterialization(for: .qwen3)
    }

    func qwenConditioningArtifact(
        for backend: SpeakSwiftly.SpeechBackend,
    ) -> StoredQwenConditioningArtifact? {
        conditioningArtifacts.first(where: { $0.manifest.backend == backend })
    }

    func qwenConditioningArtifact(
        for backend: SpeakSwiftly.SpeechBackend,
        modelRepo: String,
    ) -> StoredQwenConditioningArtifact? {
        conditioningArtifacts.first {
            $0.manifest.backend == backend && $0.manifest.modelRepo == modelRepo
        }
    }
}
