import Foundation
import TextForSpeech

struct RawBatchItem: Decodable {
    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfile = "text_profile"
        case textProfileID = "text_profile_id"
        case requestContext = "request_context"
        case cwd
        case repoRoot = "repo_root"
        case sourceFormat = "source_format"
        case inputTextContext = "input_text_context"
        case textFormat = "text_format"
        case nestedSourceFormat = "nested_source_format"
    }

    let artifactID: String?
    let text: String?
    let textProfile: SpeakSwiftly.TextProfileID?
    let requestContext: SpeakSwiftly.RequestContext?
    let cwd: String?
    let repoRoot: String?
    let sourceFormat: TextForSpeech.SourceFormat?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try Self.rejectRemovedGenerationContextKeys(in: container)

        artifactID = try container.decodeIfPresent(String.self, forKey: .artifactID)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        textProfile = try container.decodeIfPresent(String.self, forKey: .textProfile)
            ?? container.decodeIfPresent(String.self, forKey: .textProfileID)
        requestContext = try container.decodeIfPresent(
            SpeakSwiftly.RequestContext.self,
            forKey: .requestContext,
        )
        sourceFormat = try container.decodeIfPresent(
            TextForSpeech.SourceFormat.self,
            forKey: .sourceFormat,
        )
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        repoRoot = try container.decodeIfPresent(String.self, forKey: .repoRoot)
    }
}

struct RawWorkerRequest: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case op
        case artifactID = "artifact_id"
        case batchID = "batch_id"
        case jobID = "job_id"
        case items
        case text
        case voiceProfile = "voice_profile"
        case profileName = "profile_name"
        case newProfileName = "new_profile_name"
        case textProfile = "text_profile"
        case textProfileID = "text_profile_id"
        case requestContext = "request_context"
        case textProfileStyle = "text_profile_style"
        case replacement
        case replacementID = "replacement_id"
        case cwd
        case repoRoot = "repo_root"
        case sourceFormat = "source_format"
        case inputTextContext = "input_text_context"
        case textFormat = "text_format"
        case nestedSourceFormat = "nested_source_format"
        case requestID = "request_id"
        case vibe
        case voiceDescription = "voice_description"
        case seedID = "seed_id"
        case seedVersion = "seed_version"
        case intendedProfileName = "intended_profile_name"
        case fallbackProfileName = "fallback_profile_name"
        case installedAt = "installed_at"
        case sourcePackage = "source_package"
        case sourceVersion = "source_version"
        case sampleMediaPath = "sample_media_path"
        case outputPath = "output_path"
        case referenceAudioPath = "reference_audio_path"
        case transcript
        case speechBackend = "speech_backend"
        case qwenPreModelTextChunking = "qwen_pre_model_text_chunking"
    }

    private struct LegacyReplacementPayload: Decodable {
        private enum LegacyMatchPayload: Decodable {
            case match(TextForSpeech.Replacement.Match)

            init(from decoder: any Decoder) throws {
                if let match = try? TextForSpeech.Replacement.Match(from: decoder) {
                    self = .match(match)
                    return
                }

                let container = try decoder.singleValueContainer()
                let rawValue = try container.decode(String.self)

                switch rawValue {
                    case "exact_phrase":
                        self = .match(.exactPhrase)
                    case "whole_token":
                        self = .match(.wholeToken)
                    default:
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "Unsupported legacy replacement match '\(rawValue)'.",
                        )
                }
            }

            var resolved: TextForSpeech.Replacement.Match {
                switch self {
                    case let .match(match):
                        match
                }
            }
        }

        private enum LegacyTransformPayload: Decodable {
            case transform(TextForSpeech.Replacement.Transform)

            init(from decoder: any Decoder) throws {
                if let transform = try? TextForSpeech.Replacement.Transform(from: decoder) {
                    self = .transform(transform)
                    return
                }

                let container = try decoder.singleValueContainer()
                let rawValue = try container.decode(String.self)

                switch rawValue {
                    case "spoken_path":
                        self = .transform(.spokenPath)
                    case "spoken_url":
                        self = .transform(.spokenURL)
                    case "spoken_identifier":
                        self = .transform(.spokenIdentifier)
                    case "spoken_code":
                        self = .transform(.spokenCode)
                    case "spell_out":
                        self = .transform(.spellOut)
                    default:
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "Unsupported legacy replacement transform '\(rawValue)'.",
                        )
                }
            }

            var resolved: TextForSpeech.Replacement.Transform {
                switch self {
                    case let .transform(transform):
                        transform
                }
            }
        }

        let id: String
        let text: String
        let replacement: String?
        let phase: TextForSpeech.Replacement.Phase
        let isCaseSensitive: Bool
        let textFormats: Set<TextForSpeech.TextFormat>
        let sourceFormats: Set<TextForSpeech.SourceFormat>
        let priority: Int

        private let transform: LegacyTransformPayload?
        private let match: LegacyMatchPayload

        func resolved() throws -> TextForSpeech.Replacement {
            if let replacement {
                return TextForSpeech.Replacement(
                    text,
                    with: replacement,
                    id: id,
                    matching: match.resolved,
                    during: phase,
                    caseSensitive: isCaseSensitive,
                    forTextFormats: textFormats,
                    forSourceFormats: sourceFormats,
                    priority: priority,
                )
            }

            guard let transform else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Replacement payload must provide either a literal 'replacement' or a 'transform'.",
                    ),
                )
            }

            if case let .literal(literal) = transform.resolved {
                return TextForSpeech.Replacement(
                    text,
                    with: literal,
                    id: id,
                    matching: match.resolved,
                    during: phase,
                    caseSensitive: isCaseSensitive,
                    forTextFormats: textFormats,
                    forSourceFormats: sourceFormats,
                    priority: priority,
                )
            }

            return TextForSpeech.Replacement(
                id: id,
                matching: match.resolved,
                using: transform.resolved,
                during: phase,
                caseSensitive: isCaseSensitive,
                forTextFormats: textFormats,
                forSourceFormats: sourceFormats,
                priority: priority,
            )
        }
    }

    let id: String?
    let op: String?
    let artifactID: String?
    let batchID: String?
    let jobID: String?
    let items: [RawBatchItem]?
    let text: String?
    let voiceProfile: String?
    let profileName: String?
    let newProfileName: String?
    let textProfile: SpeakSwiftly.TextProfileID?
    let textProfileID: String?
    let requestContext: SpeakSwiftly.RequestContext?
    let textProfileStyle: TextForSpeech.BuiltInProfileStyle?
    let replacement: TextForSpeech.Replacement?
    let replacementID: String?
    let cwd: String?
    let repoRoot: String?
    let sourceFormat: TextForSpeech.SourceFormat?
    let requestID: String?
    let vibe: SpeakSwiftly.Vibe?
    let voiceDescription: String?
    let seedID: String?
    let seedVersion: String?
    let intendedProfileName: String?
    let fallbackProfileName: String?
    let installedAt: String?
    let sourcePackage: String?
    let sourceVersion: String?
    let sampleMediaPath: String?
    let outputPath: String?
    let referenceAudioPath: String?
    let transcript: String?
    let speechBackend: SpeakSwiftly.SpeechBackend?
    let qwenPreModelTextChunking: Bool?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try Self.rejectRemovedGenerationContextKeys(in: container)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        op = try container.decodeIfPresent(String.self, forKey: .op)
        artifactID = try container.decodeIfPresent(String.self, forKey: .artifactID)
        batchID = try container.decodeIfPresent(String.self, forKey: .batchID)
        jobID = try container.decodeIfPresent(String.self, forKey: .jobID)
        items = try container.decodeIfPresent([RawBatchItem].self, forKey: .items)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        voiceProfile = try container.decodeIfPresent(String.self, forKey: .voiceProfile)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName)
        newProfileName = try container.decodeIfPresent(String.self, forKey: .newProfileName)
        textProfile = try container.decodeIfPresent(String.self, forKey: .textProfile)
        textProfileID = try container.decodeIfPresent(String.self, forKey: .textProfileID)
        requestContext = try container.decodeIfPresent(
            SpeakSwiftly.RequestContext.self,
            forKey: .requestContext,
        )
        sourceFormat = try container.decodeIfPresent(
            TextForSpeech.SourceFormat.self,
            forKey: .sourceFormat,
        )
        textProfileStyle = try container.decodeIfPresent(
            TextForSpeech.BuiltInProfileStyle.self,
            forKey: .textProfileStyle,
        )
        replacement = try Self.decodeReplacementIfPresent(in: container, forKey: .replacement)
        replacementID = try container.decodeIfPresent(String.self, forKey: .replacementID)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        repoRoot = try container.decodeIfPresent(String.self, forKey: .repoRoot)
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
        vibe = try container.decodeIfPresent(SpeakSwiftly.Vibe.self, forKey: .vibe)
        voiceDescription = try container.decodeIfPresent(String.self, forKey: .voiceDescription)
        seedID = try container.decodeIfPresent(String.self, forKey: .seedID)
        seedVersion = try container.decodeIfPresent(String.self, forKey: .seedVersion)
        intendedProfileName = try container.decodeIfPresent(String.self, forKey: .intendedProfileName)
        fallbackProfileName = try container.decodeIfPresent(String.self, forKey: .fallbackProfileName)
        installedAt = try container.decodeIfPresent(String.self, forKey: .installedAt)
        sourcePackage = try container.decodeIfPresent(String.self, forKey: .sourcePackage)
        sourceVersion = try container.decodeIfPresent(String.self, forKey: .sourceVersion)
        sampleMediaPath = try container.decodeIfPresent(String.self, forKey: .sampleMediaPath)
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath)
        referenceAudioPath = try container.decodeIfPresent(String.self, forKey: .referenceAudioPath)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        speechBackend = try container.decodeIfPresent(SpeakSwiftly.SpeechBackend.self, forKey: .speechBackend)
        qwenPreModelTextChunking = try container.decodeIfPresent(Bool.self, forKey: .qwenPreModelTextChunking)
    }

    static func resolveSpeechTextInput(
        id: String,
        text: String?,
        textProfileID: String?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) throws -> (
        text: String,
        textProfileID: SpeakSwiftly.TextProfileID?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) {
        let resolvedText = try WorkerRequest.requireNonEmpty(text, field: "text", id: id)
        let resolvedTextProfileID = textProfileID?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil

        return (
            text: resolvedText,
            textProfileID: resolvedTextProfileID,
            sourceFormat: sourceFormat,
        )
    }

    static func resolveBatchItems(
        id: String,
        rawItems: [RawBatchItem]?,
    ) throws -> [SpeakSwiftly.GenerationJobItem] {
        guard let rawItems, !rawItems.isEmpty else {
            throw WorkerError(
                code: .invalidRequest,
                message: "Request '\(id)' must include a non-empty 'items' array for batch generation.",
            )
        }

        var seenArtifactIDs = Set<String>()
        return try rawItems.enumerated().map { index, rawItem in
            let itemID = "\(id).items[\(index)]"
            let resolved = try resolveSpeechTextInput(
                id: itemID,
                text: rawItem.text,
                textProfileID: rawItem.textProfile,
                sourceFormat: rawItem.sourceFormat,
            )
            let requestContext = requestContext(
                cwd: rawItem.cwd,
                repoRoot: rawItem.repoRoot,
                base: rawItem.requestContext,
            )
            let artifactID = rawItem.artifactID?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil
                ?? "\(id)-artifact-\(index + 1)"
            guard seenArtifactIDs.insert(artifactID).inserted else {
                throw WorkerError(
                    code: .invalidRequest,
                    message: "Request '\(id)' contains duplicate batch artifact id '\(artifactID)'. Each batch item must resolve to a unique artifact id.",
                )
            }

            return SpeakSwiftly.GenerationJobItem(
                artifactID: artifactID,
                text: resolved.text,
                textProfile: resolved.textProfileID,
                sourceFormat: resolved.sourceFormat,
                requestContext: requestContext,
            )
        }
    }

    static func requestContext(
        cwd: String?,
        repoRoot: String?,
        base: SpeakSwiftly.RequestContext? = nil,
    ) -> SpeakSwiftly.RequestContext? {
        let resolvedCWD = cwd ?? base?.cwd
        let resolvedRepoRoot = repoRoot ?? base?.repoRoot
        if resolvedCWD == nil, resolvedRepoRoot == nil {
            return base
        }

        return SpeakSwiftly.RequestContext(
            source: base?.source,
            topic: base?.topic,
            cwd: resolvedCWD,
            repoRoot: resolvedRepoRoot,
            attributes: base?.attributes ?? [:],
        )
    }

    static func resolveProfileSeed(
        id: String,
        raw: RawWorkerRequest,
        fallbackProfileName: String,
    ) throws -> SpeakSwiftly.ProfileSeed {
        let seedID = try WorkerRequest.requireNonEmpty(raw.seedID, field: "seed_id", id: id)
        let seedVersion = try WorkerRequest.requireNonEmpty(raw.seedVersion, field: "seed_version", id: id)
        let sourcePackage = try WorkerRequest.requireNonEmpty(raw.sourcePackage, field: "source_package", id: id)
        let intendedProfileName = raw.intendedProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil
            ?? fallbackProfileName
        let installedAt: Date
        if let rawInstalledAt = raw.installedAt?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil {
            guard let parsedDate = ISO8601DateFormatter().date(from: rawInstalledAt) else {
                throw WorkerError(
                    code: .invalidRequest,
                    message: "Request '\(id)' has an invalid 'installed_at' value. Use an ISO 8601 timestamp such as '2026-05-02T12:00:00Z'.",
                )
            }

            installedAt = parsedDate
        } else {
            installedAt = Date()
        }

        return SpeakSwiftly.ProfileSeed(
            seedID: seedID,
            seedVersion: seedVersion,
            intendedProfileName: intendedProfileName,
            fallbackProfileName: raw.fallbackProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil,
            installedAt: installedAt,
            sourcePackage: sourcePackage,
            sourceVersion: raw.sourceVersion?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil,
            sampleMediaPath: raw.sampleMediaPath?.trimmingCharacters(in: .whitespacesAndNewlines).emptyAsNil,
        )
    }

    static func decodeSourceFormat(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
    ) throws -> TextForSpeech.SourceFormat? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        guard let format = TextForSpeech.SourceFormat(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unsupported \(key.stringValue) value '\(raw)'.",
            )
        }

        return format
    }

    private static func decodeReplacementIfPresent(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
    ) throws -> TextForSpeech.Replacement? {
        guard container.contains(key) else { return nil }

        do {
            return try container.decodeIfPresent(TextForSpeech.Replacement.self, forKey: key)
        } catch {
            return try container
                .decodeIfPresent(LegacyReplacementPayload.self, forKey: key)?
                .resolved()
        }
    }
}

private extension RawBatchItem {
    static func rejectRemovedGenerationContextKeys(
        in container: KeyedDecodingContainer<CodingKeys>,
    ) throws {
        try rejectRemovedGenerationContextKeysInContainer(
            in: container,
            keys: [
                .inputTextContext,
                .textFormat,
                .nestedSourceFormat,
            ],
        )
    }
}

private extension RawWorkerRequest {
    static func rejectRemovedGenerationContextKeys(
        in container: KeyedDecodingContainer<CodingKeys>,
    ) throws {
        try rejectRemovedGenerationContextKeysInContainer(
            in: container,
            keys: [
                .inputTextContext,
                .textFormat,
                .nestedSourceFormat,
            ],
        )
    }
}

private func rejectRemovedGenerationContextKeysInContainer<Key: CodingKey>(
    in container: KeyedDecodingContainer<Key>,
    keys: [Key],
) throws {
    for key in keys where container.contains(key) {
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Generation context key '\(key.stringValue)' was removed. Use 'source_format' only for whole-source input, move path and request metadata into 'request_context', and omit source hints for mixed prose, Markdown, HTML, logs, CLI output, and agent text.",
        )
    }
}

private extension String {
    var emptyAsNil: String? {
        isEmpty ? nil : self
    }
}
