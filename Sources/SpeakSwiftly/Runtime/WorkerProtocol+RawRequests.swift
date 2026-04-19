import Foundation
import TextForSpeech

struct RawBatchItem: Decodable {
    let artifactID: String?
    let text: String?
    let textProfileID: String?
    let cwd: String?
    let repoRoot: String?
    let textFormat: TextForSpeech.TextFormat?
    let nestedSourceFormat: TextForSpeech.SourceFormat?
    let sourceFormat: TextForSpeech.SourceFormat?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfileID = "text_profile_id"
        case cwd
        case repoRoot = "repo_root"
        case textFormat = "text_format"
        case nestedSourceFormat = "nested_source_format"
        case sourceFormat = "source_format"
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
        case profileName = "profile_name"
        case newProfileName = "new_profile_name"
        case textProfileID = "text_profile_id"
        case textProfileStyle = "text_profile_style"
        case replacement
        case replacementID = "replacement_id"
        case cwd
        case repoRoot = "repo_root"
        case textFormat = "text_format"
        case nestedSourceFormat = "nested_source_format"
        case sourceFormat = "source_format"
        case requestID = "request_id"
        case vibe
        case voiceDescription = "voice_description"
        case outputPath = "output_path"
        case referenceAudioPath = "reference_audio_path"
        case transcript
        case speechBackend = "speech_backend"
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
    let profileName: String?
    let newProfileName: String?
    let textProfileID: String?
    let textProfileStyle: TextForSpeech.BuiltInProfileStyle?
    let replacement: TextForSpeech.Replacement?
    let replacementID: String?
    let cwd: String?
    let repoRoot: String?
    let textFormat: TextForSpeech.TextFormat?
    let nestedSourceFormat: TextForSpeech.SourceFormat?
    let sourceFormat: TextForSpeech.SourceFormat?
    let requestID: String?
    let vibe: SpeakSwiftly.Vibe?
    let voiceDescription: String?
    let outputPath: String?
    let referenceAudioPath: String?
    let transcript: String?
    let speechBackend: SpeakSwiftly.SpeechBackend?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        op = try container.decodeIfPresent(String.self, forKey: .op)
        artifactID = try container.decodeIfPresent(String.self, forKey: .artifactID)
        batchID = try container.decodeIfPresent(String.self, forKey: .batchID)
        jobID = try container.decodeIfPresent(String.self, forKey: .jobID)
        items = try container.decodeIfPresent([RawBatchItem].self, forKey: .items)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName)
        newProfileName = try container.decodeIfPresent(String.self, forKey: .newProfileName)
        textProfileID = try container.decodeIfPresent(String.self, forKey: .textProfileID)
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
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath)
        referenceAudioPath = try container.decodeIfPresent(String.self, forKey: .referenceAudioPath)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        speechBackend = try container.decodeIfPresent(SpeakSwiftly.SpeechBackend.self, forKey: .speechBackend)

        let rawTextFormat = try container.decodeIfPresent(String.self, forKey: .textFormat)
        let explicitNestedSourceFormat = try Self.decodeSourceFormat(
            in: container,
            forKey: .nestedSourceFormat,
        )
        let explicitSourceFormat = try Self.decodeSourceFormat(
            in: container,
            forKey: .sourceFormat,
        )

        if let rawTextFormat {
            if let parsedTextFormat = TextForSpeech.TextFormat(rawValue: rawTextFormat) {
                textFormat = parsedTextFormat
                sourceFormat = explicitSourceFormat
            } else if let compatibility = Self.legacyCompatibility(forRawValue: rawTextFormat) {
                textFormat = compatibility.textFormat
                sourceFormat = explicitSourceFormat ?? compatibility.sourceFormat
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .textFormat,
                    in: container,
                    debugDescription: "Unsupported text_format value '\(rawTextFormat)'.",
                )
            }
        } else {
            textFormat = nil
            sourceFormat = explicitSourceFormat
        }

        nestedSourceFormat = explicitNestedSourceFormat
    }

    static func resolveSpeechTextInput(
        id: String,
        text: String?,
        textProfileID: String?,
        cwd: String?,
        repoRoot: String?,
        textFormat: TextForSpeech.TextFormat?,
        nestedSourceFormat: TextForSpeech.SourceFormat?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) throws -> (
        text: String,
        textProfileID: String?,
        textContext: TextForSpeech.Context?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) {
        let resolvedText = try WorkerRequest.requireNonEmpty(text, field: "text", id: id)
        let resolvedTextProfileID = textProfileID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if sourceFormat != nil, textFormat != nil || nestedSourceFormat != nil {
            throw WorkerError(
                code: .invalidRequest,
                message: "Request '\(id)' cannot combine the whole-source lane (`source_format`) with mixed-text lane fields (`text_format` or `nested_source_format`).",
            )
        }
        let textContext = TextForSpeech.Context(
            cwd: cwd,
            repoRoot: repoRoot,
            textFormat: textFormat,
            nestedSourceFormat: nestedSourceFormat,
        )
        .nilIfEmpty

        return (
            text: resolvedText,
            textProfileID: resolvedTextProfileID,
            textContext: textContext,
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
                textProfileID: rawItem.textProfileID,
                cwd: rawItem.cwd,
                repoRoot: rawItem.repoRoot,
                textFormat: rawItem.textFormat,
                nestedSourceFormat: rawItem.nestedSourceFormat,
                sourceFormat: rawItem.sourceFormat,
            )
            let artifactID = rawItem.artifactID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
                textProfileID: resolved.textProfileID,
                textContext: resolved.textContext,
                sourceFormat: resolved.sourceFormat,
            )
        }
    }

    private static func decodeSourceFormat(
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

    private static func decodeReplacementsIfPresent(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
    ) throws -> [TextForSpeech.Replacement]? {
        guard container.contains(key) else { return nil }

        do {
            return try container.decodeIfPresent([TextForSpeech.Replacement].self, forKey: key)
        } catch {
            return try container
                .decodeIfPresent([LegacyReplacementPayload].self, forKey: key)?
                .map { try $0.resolved() }
        }
    }

    private static func legacyCompatibility(
        forRawValue rawValue: String,
    ) -> (textFormat: TextForSpeech.TextFormat?, sourceFormat: TextForSpeech.SourceFormat?)? {
        switch rawValue {
            case TextForSpeech.TextFormat.plain.rawValue: (.plain, nil)
            case TextForSpeech.TextFormat.markdown.rawValue: (.markdown, nil)
            case TextForSpeech.TextFormat.html.rawValue: (.html, nil)
            case TextForSpeech.TextFormat.log.rawValue: (.log, nil)
            case TextForSpeech.TextFormat.cli.rawValue: (.cli, nil)
            case TextForSpeech.TextFormat.list.rawValue: (.list, nil)
            case TextForSpeech.SourceFormat.generic.rawValue: (nil, .generic)
            case TextForSpeech.SourceFormat.swift.rawValue: (nil, .swift)
            case TextForSpeech.SourceFormat.python.rawValue: (nil, .python)
            case TextForSpeech.SourceFormat.rust.rawValue: (nil, .rust)
            default: nil
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension TextForSpeech.Context {
    var nilIfEmpty: TextForSpeech.Context? {
        cwd == nil && repoRoot == nil && textFormat == nil && nestedSourceFormat == nil ? nil : self
    }
}
