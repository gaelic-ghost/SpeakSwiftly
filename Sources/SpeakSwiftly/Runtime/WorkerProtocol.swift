import Foundation
import TextForSpeech

// MARK: - Request Envelope

struct RawBatchItem: Decodable, Sendable {
    let artifactID: String?
    let text: String?
    let textProfileName: String?
    let cwd: String?
    let repoRoot: String?
    let textFormat: TextForSpeech.TextFormat?
    let nestedSourceFormat: TextForSpeech.SourceFormat?
    let sourceFormat: TextForSpeech.SourceFormat?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfileName = "text_profile_name"
        case cwd
        case repoRoot = "repo_root"
        case textFormat = "text_format"
        case nestedSourceFormat = "nested_source_format"
        case sourceFormat = "source_format"
    }
}

struct RawWorkerRequest: Decodable, Sendable {
    let id: String?
    let op: String?
    let artifactID: String?
    let batchID: String?
    let jobID: String?
    let items: [RawBatchItem]?
    let text: String?
    let profileName: String?
    let textProfileName: String?
    let textProfileID: String?
    let textProfileDisplayName: String?
    let textProfile: TextForSpeech.Profile?
    let replacements: [TextForSpeech.Replacement]?
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

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case artifactID = "artifact_id"
        case batchID = "batch_id"
        case jobID = "job_id"
        case items
        case text
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
        case textProfileID = "text_profile_id"
        case textProfileDisplayName = "text_profile_display_name"
        case textProfile = "text_profile"
        case replacements
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
        textProfileName = try container.decodeIfPresent(String.self, forKey: .textProfileName)
        textProfileID = try container.decodeIfPresent(String.self, forKey: .textProfileID)
        textProfileDisplayName = try container.decodeIfPresent(String.self, forKey: .textProfileDisplayName)
        textProfile = try container.decodeIfPresent(TextForSpeech.Profile.self, forKey: .textProfile)
        replacements = try container.decodeIfPresent([TextForSpeech.Replacement].self, forKey: .replacements)
        replacement = try container.decodeIfPresent(TextForSpeech.Replacement.self, forKey: .replacement)
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
            forKey: .nestedSourceFormat
        )
        let explicitSourceFormat = try Self.decodeSourceFormat(
            in: container,
            forKey: .sourceFormat
        )

        if let rawTextFormat {
            if let parsedTextFormat = TextForSpeech.TextFormat(rawValue: rawTextFormat) {
                textFormat = parsedTextFormat
                sourceFormat = explicitSourceFormat
            } else if let legacyFormat = TextForSpeech.Format(rawValue: rawTextFormat) {
                let compatibility = Self.legacyCompatibility(for: legacyFormat)
                textFormat = compatibility.textFormat
                sourceFormat = explicitSourceFormat ?? compatibility.sourceFormat
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .textFormat,
                    in: container,
                    debugDescription: "Unsupported text_format value '\(rawTextFormat)'."
                )
            }
        } else {
            textFormat = nil
            sourceFormat = explicitSourceFormat
        }

        nestedSourceFormat = explicitNestedSourceFormat
    }

    private static func decodeSourceFormat(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> TextForSpeech.SourceFormat? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        guard let format = TextForSpeech.SourceFormat(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unsupported \(key.stringValue) value '\(raw)'."
            )
        }

        return format
    }

    private static func legacyCompatibility(
        for format: TextForSpeech.Format
    ) -> (textFormat: TextForSpeech.TextFormat?, sourceFormat: TextForSpeech.SourceFormat?) {
        switch format {
        case .plain: (.plain, nil)
        case .markdown: (.markdown, nil)
        case .html: (.html, nil)
        case .log: (.log, nil)
        case .cli: (.cli, nil)
        case .list: (.list, nil)
        case .source: (nil, .generic)
        case .swift: (nil, .swift)
        case .python: (nil, .python)
        case .rust: (nil, .rust)
        }
    }

    static func resolveSpeechTextInput(
        id: String,
        text: String?,
        textProfileName: String?,
        cwd: String?,
        repoRoot: String?,
        textFormat: TextForSpeech.TextFormat?,
        nestedSourceFormat: TextForSpeech.SourceFormat?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) throws -> (
        text: String,
        textProfileName: String?,
        textContext: TextForSpeech.Context?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) {
        let resolvedText = try WorkerRequest.requireNonEmpty(text, field: "text", id: id)
        let resolvedTextProfileName = textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if sourceFormat != nil && (textFormat != nil || nestedSourceFormat != nil) {
            throw WorkerError(
                code: .invalidRequest,
                message: "Request '\(id)' cannot combine the whole-source lane (`source_format`) with mixed-text lane fields (`text_format` or `nested_source_format`)."
            )
        }
        let textContext = TextForSpeech.Context(
            cwd: cwd,
            repoRoot: repoRoot,
            textFormat: textFormat,
            nestedSourceFormat: nestedSourceFormat
        ).nilIfEmpty

        return (
            text: resolvedText,
            textProfileName: resolvedTextProfileName,
            textContext: textContext,
            sourceFormat: sourceFormat
        )
    }

    static func resolveBatchItems(
        id: String,
        rawItems: [RawBatchItem]?
    ) throws -> [SpeakSwiftly.GenerationJobItem] {
        guard let rawItems, !rawItems.isEmpty else {
            throw WorkerError(
                code: .invalidRequest,
                message: "Request '\(id)' must include a non-empty 'items' array for batch generation."
            )
        }

        var seenArtifactIDs = Set<String>()
        return try rawItems.enumerated().map { index, rawItem in
            let itemID = "\(id).items[\(index)]"
            let resolved = try resolveSpeechTextInput(
                id: itemID,
                text: rawItem.text,
                textProfileName: rawItem.textProfileName,
                cwd: rawItem.cwd,
                repoRoot: rawItem.repoRoot,
                textFormat: rawItem.textFormat,
                nestedSourceFormat: rawItem.nestedSourceFormat,
                sourceFormat: rawItem.sourceFormat
            )
            let artifactID = rawItem.artifactID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "\(id)-artifact-\(index + 1)"
            guard seenArtifactIDs.insert(artifactID).inserted else {
                throw WorkerError(
                    code: .invalidRequest,
                    message: "Request '\(id)' contains duplicate batch artifact id '\(artifactID)'. Each batch item must resolve to a unique artifact id."
                )
            }

            return SpeakSwiftly.GenerationJobItem(
                artifactID: artifactID,
                text: resolved.text,
                textProfileName: resolved.textProfileName,
                textContext: resolved.textContext,
                sourceFormat: resolved.sourceFormat
            )
        }
    }
}

enum WorkerRequest: Sendable, Equatable {
    case queueSpeech(
        id: String,
        text: String,
        profileName: String,
        textProfileName: String?,
        jobType: SpeechJobType,
        textContext: TextForSpeech.Context?,
        sourceFormat: TextForSpeech.SourceFormat?
    )
    case queueBatch(
        id: String,
        profileName: String,
        items: [SpeakSwiftly.GenerationJobItem]
    )
    case generatedFile(id: String, artifactID: String)
    case generatedFiles(id: String)
    case generatedBatch(id: String, batchID: String)
    case generatedBatches(id: String)
    case expireGenerationJob(id: String, jobID: String)
    case generationJob(id: String, jobID: String)
    case generationJobs(id: String)
    case createProfile(
        id: String,
        profileName: String,
        text: String,
        vibe: SpeakSwiftly.Vibe,
        voiceDescription: String,
        outputPath: String?,
        cwd: String?
    )
    case createClone(
        id: String,
        profileName: String,
        referenceAudioPath: String,
        vibe: SpeakSwiftly.Vibe,
        transcript: String?,
        cwd: String?
    )
    case listProfiles(id: String)
    case removeProfile(id: String, profileName: String)
    case textProfileActive(id: String)
    case textProfileBase(id: String)
    case textProfile(id: String, name: String)
    case textProfiles(id: String)
    case textProfileEffective(id: String, name: String?)
    case textProfilePersistence(id: String)
    case loadTextProfiles(id: String)
    case saveTextProfiles(id: String)
    case createTextProfile(id: String, profileID: String, profileName: String, replacements: [TextForSpeech.Replacement])
    case storeTextProfile(id: String, profile: TextForSpeech.Profile)
    case useTextProfile(id: String, profile: TextForSpeech.Profile)
    case removeTextProfile(id: String, profileName: String)
    case resetTextProfile(id: String)
    case addTextReplacement(id: String, replacement: TextForSpeech.Replacement, profileName: String?)
    case replaceTextReplacement(id: String, replacement: TextForSpeech.Replacement, profileName: String?)
    case removeTextReplacement(id: String, replacementID: String, profileName: String?)
    case listQueue(id: String, queueType: WorkerQueueType)
    case status(id: String)
    case switchSpeechBackend(id: String, speechBackend: SpeakSwiftly.SpeechBackend)
    case playback(id: String, action: PlaybackAction)
    case clearQueue(id: String)
    case cancelRequest(id: String, requestID: String)

    var id: String {
        switch self {
        case .queueSpeech(id: let id, text: _, profileName: _, textProfileName: _, jobType: _, textContext: _, sourceFormat: _),
             .queueBatch(id: let id, profileName: _, items: _),
             .generatedFile(let id, _),
             .generatedFiles(let id),
             .generatedBatch(let id, _),
             .generatedBatches(let id),
             .expireGenerationJob(let id, _),
             .generationJob(let id, _),
             .generationJobs(let id),
             .createProfile(let id, _, _, _, _, _, _),
             .createClone(let id, _, _, _, _, _),
             .listProfiles(let id),
             .removeProfile(let id, _),
             .textProfileActive(let id),
             .textProfileBase(let id),
             .textProfile(let id, _),
             .textProfiles(let id),
             .textProfileEffective(let id, _),
             .textProfilePersistence(let id),
             .loadTextProfiles(let id),
             .saveTextProfiles(let id),
             .createTextProfile(let id, _, _, _),
             .storeTextProfile(let id, _),
             .useTextProfile(let id, _),
             .removeTextProfile(let id, _),
             .resetTextProfile(let id),
             .addTextReplacement(let id, _, _),
             .replaceTextReplacement(let id, _, _),
             .removeTextReplacement(let id, _, _),
             .listQueue(let id, _),
             .status(let id),
             .switchSpeechBackend(let id, _),
             .playback(let id, _),
             .clearQueue(let id),
             .cancelRequest(let id, _):
            id
        }
    }

    var opName: String {
        switch self {
        case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: .live, textContext: _, sourceFormat: _):
            "queue_speech_live"
        case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: .file, textContext: _, sourceFormat: _):
            "queue_speech_file"
        case .queueBatch:
            "queue_speech_batch"
        case .generatedFile:
            "generated_file"
        case .generatedFiles:
            "generated_files"
        case .generatedBatch:
            "generated_batch"
        case .generatedBatches:
            "generated_batches"
        case .expireGenerationJob:
            "expire_generation_job"
        case .generationJob:
            "generation_job"
        case .generationJobs:
            "generation_jobs"
        case .createProfile:
            "create_profile"
        case .createClone:
            "create_clone"
        case .listProfiles:
            "list_profiles"
        case .removeProfile:
            "remove_profile"
        case .textProfileActive:
            "text_profile_active"
        case .textProfileBase:
            "text_profile_base"
        case .textProfile:
            "text_profile"
        case .textProfiles:
            "text_profiles"
        case .textProfileEffective:
            "text_profile_effective"
        case .textProfilePersistence:
            "text_profile_persistence"
        case .loadTextProfiles:
            "load_text_profiles"
        case .saveTextProfiles:
            "save_text_profiles"
        case .createTextProfile:
            "create_text_profile"
        case .storeTextProfile:
            "store_text_profile"
        case .useTextProfile:
            "use_text_profile"
        case .removeTextProfile:
            "remove_text_profile"
        case .resetTextProfile:
            "reset_text_profile"
        case .addTextReplacement:
            "add_text_replacement"
        case .replaceTextReplacement:
            "replace_text_replacement"
        case .removeTextReplacement:
            "remove_text_replacement"
        case .listQueue(_, .generation):
            "list_queue_generation"
        case .listQueue(_, .playback):
            "list_queue_playback"
        case .status:
            "status"
        case .switchSpeechBackend:
            "set_speech_backend"
        case .playback(_, .pause):
            "playback_pause"
        case .playback(_, .resume):
            "playback_resume"
        case .playback(_, .state):
            "playback_state"
        case .clearQueue:
            "clear_queue"
        case .cancelRequest:
            "cancel_request"
        }
    }

    var isSpeechRequest: Bool {
        switch self {
        case .queueSpeech, .queueBatch:
            return true
        default:
            return false
        }
    }

    var requiresPlayback: Bool {
        switch self {
        case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: .live, textContext: _, sourceFormat: _):
            return true
        default:
            return false
        }
    }

    var acknowledgesEnqueueImmediately: Bool {
        switch self {
        case .queueSpeech, .queueBatch:
            return true
        default:
            return false
        }
    }

    var emitsTerminalSuccessAfterAcknowledgement: Bool {
        switch self {
        case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: .file, textContext: _, sourceFormat: _),
             .queueBatch:
            return true
        default:
            return false
        }
    }

    var isImmediateControlOperation: Bool {
        switch self {
        case .generatedFile,
             .generatedFiles,
             .generatedBatch,
             .generatedBatches,
             .expireGenerationJob,
             .generationJob,
             .generationJobs,
             .textProfileActive,
             .textProfileBase,
             .textProfile,
             .textProfiles,
             .textProfileEffective,
             .textProfilePersistence,
             .loadTextProfiles,
             .saveTextProfiles,
             .createTextProfile,
             .storeTextProfile,
             .useTextProfile,
             .removeTextProfile,
             .resetTextProfile,
             .addTextReplacement,
             .replaceTextReplacement,
             .removeTextReplacement,
             .listQueue,
             .status,
             .switchSpeechBackend,
             .playback,
             .clearQueue,
             .cancelRequest:
            return true
        default:
            return false
        }
    }

    var profileName: String? {
        switch self {
        case .queueSpeech(id: _, text: _, profileName: let profileName, textProfileName: _, jobType: _, textContext: _, sourceFormat: _),
             .queueBatch(id: _, profileName: let profileName, items: _),
             .createProfile(_, let profileName, _, _, _, _, _),
             .createClone(_, let profileName, _, _, _, _),
             .removeProfile(_, let profileName):
            profileName
        case .generatedFile,
             .generatedFiles,
             .generatedBatch,
             .generatedBatches,
             .expireGenerationJob,
             .generationJob,
             .generationJobs,
             .textProfileActive,
             .textProfileBase,
             .textProfiles,
             .textProfilePersistence,
             .loadTextProfiles,
             .saveTextProfiles,
             .storeTextProfile,
             .useTextProfile,
             .resetTextProfile,
             .listProfiles,
             .listQueue,
             .status,
             .switchSpeechBackend,
             .playback,
             .clearQueue,
             .cancelRequest:
            nil
        case .textProfile(_, let name),
             .removeTextProfile(_, let name):
            name
        case .textProfileEffective(_, let name),
             .addTextReplacement(_, _, let name),
             .replaceTextReplacement(_, _, let name),
             .removeTextReplacement(_, _, let name):
            name
        case .createTextProfile(_, let profileID, _, _):
            profileID
        }
    }

    var textProfileName: String? {
        switch self {
        case .queueSpeech(id: _, text: _, profileName: _, textProfileName: let textProfileName, jobType: _, textContext: _, sourceFormat: _):
            return textProfileName
        case .queueBatch(id: _, profileName: _, items: let items):
            let names = Set(items.compactMap(\.textProfileName))
            return names.count == 1 ? names.first : nil
        case .generatedFile,
             .generatedFiles,
             .generatedBatch,
             .generatedBatches,
             .expireGenerationJob,
             .generationJob,
             .generationJobs,
             .createProfile,
             .createClone,
             .listProfiles,
             .removeProfile,
             .textProfileActive,
             .textProfileBase,
             .textProfile,
             .textProfiles,
             .textProfileEffective,
             .textProfilePersistence,
             .loadTextProfiles,
             .saveTextProfiles,
             .createTextProfile,
             .storeTextProfile,
             .useTextProfile,
             .removeTextProfile,
             .resetTextProfile,
             .addTextReplacement,
             .replaceTextReplacement,
             .removeTextReplacement,
             .listQueue,
             .status,
             .switchSpeechBackend,
             .playback,
             .clearQueue,
             .cancelRequest:
            return nil
        }
    }

    var textContext: TextForSpeech.Context? {
        switch self {
        case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: _, textContext: let textContext, sourceFormat: _):
            textContext
        case .queueBatch:
            nil
        case .generatedFile,
             .generatedFiles,
             .generatedBatch,
             .generatedBatches,
             .expireGenerationJob,
             .generationJob,
             .generationJobs,
             .createProfile,
             .createClone,
             .listProfiles,
             .removeProfile,
             .textProfileActive,
             .textProfileBase,
             .textProfile,
             .textProfiles,
             .textProfileEffective,
             .textProfilePersistence,
             .loadTextProfiles,
             .saveTextProfiles,
             .createTextProfile,
             .storeTextProfile,
             .useTextProfile,
             .removeTextProfile,
             .resetTextProfile,
             .addTextReplacement,
             .replaceTextReplacement,
             .removeTextReplacement,
             .listQueue,
             .status,
             .switchSpeechBackend,
             .playback,
             .clearQueue,
             .cancelRequest:
            nil
        }
    }

    var sourceFormat: TextForSpeech.SourceFormat? {
        switch self {
        case .queueSpeech(id: _, text: _, profileName: _, textProfileName: _, jobType: _, textContext: _, sourceFormat: let sourceFormat):
            sourceFormat
        case .queueBatch:
            nil
        case .generatedFile,
             .generatedFiles,
             .generatedBatch,
             .generatedBatches,
             .expireGenerationJob,
             .generationJob,
             .generationJobs,
             .createProfile,
             .createClone,
             .listProfiles,
             .removeProfile,
             .textProfileActive,
             .textProfileBase,
             .textProfile,
             .textProfiles,
             .textProfileEffective,
             .textProfilePersistence,
             .loadTextProfiles,
             .saveTextProfiles,
             .createTextProfile,
             .storeTextProfile,
             .useTextProfile,
             .removeTextProfile,
             .resetTextProfile,
             .addTextReplacement,
             .replaceTextReplacement,
             .removeTextReplacement,
             .listQueue,
             .status,
             .switchSpeechBackend,
             .playback,
             .clearQueue,
             .cancelRequest:
            nil
        }
    }

    static func decode(from line: String, decoder: JSONDecoder = JSONDecoder()) throws -> WorkerRequest {
        let data = Data(line.utf8)
        let raw: RawWorkerRequest

        do {
            raw = try decoder.decode(RawWorkerRequest.self, from: data)
        } catch let error as DecodingError {
            throw WorkerError(
                code: .invalidRequest,
                message: "The request line contains an invalid field value or shape. \(describeDecodingError(error))"
            )
        } catch {
            throw WorkerError(code: .invalidJSON, message: "The request line is not valid JSON. Each request must be a single JSON object on one line.")
        }

        guard let id = raw.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw WorkerError(code: .invalidRequest, message: "The request is missing a non-empty 'id' field.")
        }

        guard let op = raw.op?.trimmingCharacters(in: .whitespacesAndNewlines), !op.isEmpty else {
            throw WorkerError(code: .invalidRequest, message: "Request '\(id)' is missing a non-empty 'op' field.")
        }

        switch op {
        case "queue_speech_live":
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            let resolved = try RawWorkerRequest.resolveSpeechTextInput(
                id: id,
                text: raw.text,
                textProfileName: raw.textProfileName,
                cwd: raw.cwd,
                repoRoot: raw.repoRoot,
                textFormat: raw.textFormat,
                nestedSourceFormat: raw.nestedSourceFormat,
                sourceFormat: raw.sourceFormat
            )
            return .queueSpeech(
                id: id,
                text: resolved.text,
                profileName: profileName,
                textProfileName: resolved.textProfileName,
                jobType: .live,
                textContext: resolved.textContext,
                sourceFormat: resolved.sourceFormat
            )

        case "queue_speech_file":
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            let resolved = try RawWorkerRequest.resolveSpeechTextInput(
                id: id,
                text: raw.text,
                textProfileName: raw.textProfileName,
                cwd: raw.cwd,
                repoRoot: raw.repoRoot,
                textFormat: raw.textFormat,
                nestedSourceFormat: raw.nestedSourceFormat,
                sourceFormat: raw.sourceFormat
            )
            return .queueSpeech(
                id: id,
                text: resolved.text,
                profileName: profileName,
                textProfileName: resolved.textProfileName,
                jobType: .file,
                textContext: resolved.textContext,
                sourceFormat: resolved.sourceFormat
            )

        case "queue_speech_batch":
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            let items = try RawWorkerRequest.resolveBatchItems(id: id, rawItems: raw.items)
            return .queueBatch(id: id, profileName: profileName, items: items)

        case "generated_file":
            let artifactID = try requireNonEmpty(raw.artifactID, field: "artifact_id", id: id)
            return .generatedFile(id: id, artifactID: artifactID)

        case "generated_files":
            return .generatedFiles(id: id)

        case "generated_batch":
            let batchID = try requireNonEmpty(raw.batchID ?? raw.jobID, field: "batch_id", id: id)
            return .generatedBatch(id: id, batchID: batchID)

        case "generated_batches":
            return .generatedBatches(id: id)

        case "expire_generation_job":
            let jobID = try requireNonEmpty(raw.jobID, field: "job_id", id: id)
            return .expireGenerationJob(id: id, jobID: jobID)

        case "generation_job":
            let jobID = try requireNonEmpty(raw.jobID, field: "job_id", id: id)
            return .generationJob(id: id, jobID: jobID)

        case "generation_jobs":
            return .generationJobs(id: id)

        case "create_profile":
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            let text = try requireNonEmpty(raw.text, field: "text", id: id)
            let vibe = try require(raw.vibe, field: "vibe", id: id)
            let voiceDescription = try requireNonEmpty(raw.voiceDescription, field: "voice_description", id: id)
            let outputPath = raw.outputPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return .createProfile(
                id: id,
                profileName: profileName,
                text: text,
                vibe: vibe,
                voiceDescription: voiceDescription,
                outputPath: outputPath,
                cwd: raw.cwd?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )

        case "create_clone":
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            let referenceAudioPath = try requireNonEmpty(raw.referenceAudioPath, field: "reference_audio_path", id: id)
            let vibe = try require(raw.vibe, field: "vibe", id: id)
            let transcript = raw.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return .createClone(
                id: id,
                profileName: profileName,
                referenceAudioPath: referenceAudioPath,
                vibe: vibe,
                transcript: transcript,
                cwd: raw.cwd?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )

        case "list_profiles":
            return .listProfiles(id: id)

        case "remove_profile":
            let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
            return .removeProfile(id: id, profileName: profileName)

        case "text_profile_active":
            return .textProfileActive(id: id)

        case "text_profile_base":
            return .textProfileBase(id: id)

        case "text_profile":
            let textProfileName = try requireNonEmpty(raw.textProfileName, field: "text_profile_name", id: id)
            return .textProfile(id: id, name: textProfileName)

        case "text_profiles":
            return .textProfiles(id: id)

        case "text_profile_effective":
            let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return .textProfileEffective(id: id, name: textProfileName)

        case "text_profile_persistence":
            return .textProfilePersistence(id: id)

        case "load_text_profiles":
            return .loadTextProfiles(id: id)

        case "save_text_profiles":
            return .saveTextProfiles(id: id)

        case "create_text_profile":
            let textProfileID = try requireNonEmpty(raw.textProfileID, field: "text_profile_id", id: id)
            let textProfileDisplayName = try requireNonEmpty(
                raw.textProfileDisplayName,
                field: "text_profile_display_name",
                id: id
            )
            return .createTextProfile(
                id: id,
                profileID: textProfileID,
                profileName: textProfileDisplayName,
                replacements: raw.replacements ?? []
            )

        case "store_text_profile":
            guard let textProfile = raw.textProfile else {
                throw WorkerError(
                    code: .invalidRequest,
                    message: "Request '\(id)' is missing a 'text_profile' object."
                )
            }
            return .storeTextProfile(id: id, profile: textProfile)

        case "use_text_profile":
            guard let textProfile = raw.textProfile else {
                throw WorkerError(
                    code: .invalidRequest,
                    message: "Request '\(id)' is missing a 'text_profile' object."
                )
            }
            return .useTextProfile(id: id, profile: textProfile)

        case "remove_text_profile":
            let textProfileName = try requireNonEmpty(raw.textProfileName, field: "text_profile_name", id: id)
            return .removeTextProfile(id: id, profileName: textProfileName)

        case "reset_text_profile":
            return .resetTextProfile(id: id)

        case "add_text_replacement":
            guard let replacement = raw.replacement else {
                throw WorkerError(
                    code: .invalidRequest,
                    message: "Request '\(id)' is missing a 'replacement' object."
                )
            }
            let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return .addTextReplacement(id: id, replacement: replacement, profileName: textProfileName)

        case "replace_text_replacement":
            guard let replacement = raw.replacement else {
                throw WorkerError(
                    code: .invalidRequest,
                    message: "Request '\(id)' is missing a 'replacement' object."
                )
            }
            let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return .replaceTextReplacement(id: id, replacement: replacement, profileName: textProfileName)

        case "remove_text_replacement":
            let replacementID = try requireNonEmpty(raw.replacementID, field: "replacement_id", id: id)
            let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return .removeTextReplacement(id: id, replacementID: replacementID, profileName: textProfileName)

        case "list_queue_generation":
            return .listQueue(id: id, queueType: .generation)

        case "list_queue_playback":
            return .listQueue(id: id, queueType: .playback)

        case "status":
            return .status(id: id)

        case "set_speech_backend":
            let speechBackend = try require(raw.speechBackend, field: "speech_backend", id: id)
            return .switchSpeechBackend(id: id, speechBackend: speechBackend)

        case "playback_pause":
            return .playback(id: id, action: .pause)

        case "playback_resume":
            return .playback(id: id, action: .resume)

        case "playback_state":
            return .playback(id: id, action: .state)

        case "clear_queue":
            return .clearQueue(id: id)

        case "cancel_request":
            let requestID = try requireNonEmpty(raw.requestID, field: "request_id", id: id)
            return .cancelRequest(id: id, requestID: requestID)

        default:
            throw WorkerError(code: .unknownOperation, message: "Request '\(id)' uses unsupported operation '\(op)'.")
        }
    }

    static func requireNonEmpty(_ value: String?, field: String, id: String) throws -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            throw WorkerError(code: .invalidRequest, message: "Request '\(id)' is missing a non-empty '\(field)' field.")
        }
        return trimmed
    }

    static func require<T>(_ value: T?, field: String, id: String) throws -> T {
        guard let value else {
            throw WorkerError(code: .invalidRequest, message: "Request '\(id)' is missing a '\(field)' field.")
        }
        return value
    }

    private static func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            context.debugDescription
        case .keyNotFound(let key, let context):
            "Missing key '\(key.stringValue)'. \(context.debugDescription)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            context.debugDescription
        @unknown default:
            "The request payload could not be decoded."
        }
    }
}

// MARK: - Response Envelope

public extension SpeakSwiftly {
    enum StatusStage: String, Codable, Sendable {
        case warmingResidentModel = "warming_resident_model"
        case residentModelReady = "resident_model_ready"
        case residentModelFailed = "resident_model_failed"
    }

    enum RequestEventName: String, Codable, Sendable {
        case queued
        case started
        case progress
    }

    enum ProgressStage: String, Codable, Sendable {
        case loadingProfile = "loading_profile"
        case generatingFileAudio = "generating_file_audio"
        case writingGeneratedFile = "writing_generated_file"
        case startingPlayback = "starting_playback"
        case bufferingAudio = "buffering_audio"
        case prerollReady = "preroll_ready"
        case playbackFinished = "playback_finished"
        case loadingProfileModel = "loading_profile_model"
        case generatingProfileAudio = "generating_profile_audio"
        case loadingCloneTranscriptionModel = "loading_clone_transcription_model"
        case transcribingCloneAudio = "transcribing_clone_audio"
        case writingProfileAssets = "writing_profile_assets"
        case exportingProfileAudio = "exporting_profile_audio"
        case removingProfile = "removing_profile"
    }

    enum QueuedReason: String, Codable, Sendable {
        case waitingForResidentModel = "waiting_for_resident_model"
        case waitingForActiveRequest = "waiting_for_active_request"
    }

    struct StatusEvent: Encodable, Sendable, Equatable {
        public let event = "worker_status"
        public let stage: StatusStage
        public let speechBackend: SpeechBackend

        enum CodingKeys: String, CodingKey {
            case event
            case stage
            case speechBackend = "speech_backend"
        }

        public init(stage: StatusStage, speechBackend: SpeechBackend) {
            self.stage = stage
            self.speechBackend = speechBackend
        }
    }

    struct QueuedEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.queued
        public let reason: QueuedReason
        public let queuePosition: Int

        enum CodingKeys: String, CodingKey {
            case id
            case event
            case reason
            case queuePosition = "queue_position"
        }

        public init(id: String, reason: QueuedReason, queuePosition: Int) {
            self.id = id
            self.reason = reason
            self.queuePosition = queuePosition
        }
    }

    struct StartedEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.started
        public let op: String

        public init(id: String, op: String) {
            self.id = id
            self.op = op
        }
    }

    struct ProgressEvent: Encodable, Sendable, Equatable {
        public let id: String
        public let event = RequestEventName.progress
        public let stage: ProgressStage

        public init(id: String, stage: ProgressStage) {
            self.id = id
            self.stage = stage
        }
    }

    struct Success: Encodable, Sendable, Equatable {
        public let id: String
        public let ok = true
        public let generatedFile: GeneratedFile?
        public let generatedFiles: [GeneratedFile]?
        public let generatedBatch: GeneratedBatch?
        public let generatedBatches: [GeneratedBatch]?
        public let generationJob: GenerationJob?
        public let generationJobs: [GenerationJob]?
        public let profileName: String?
        public let profilePath: String?
        public let profiles: [ProfileSummary]?
        public let textProfile: TextForSpeech.Profile?
        public let textProfiles: [TextForSpeech.Profile]?
        public let textProfilePath: String?
        public let activeRequest: ActiveRequest?
        public let queue: [QueuedRequest]?
        public let playbackState: PlaybackStateSnapshot?
        public let status: StatusEvent?
        public let speechBackend: SpeechBackend?
        public let clearedCount: Int?
        public let cancelledRequestID: String?

        enum CodingKeys: String, CodingKey {
            case id
            case ok
            case generatedFile = "generated_file"
            case generatedFiles = "generated_files"
            case generatedBatch = "generated_batch"
            case generatedBatches = "generated_batches"
            case generationJob = "generation_job"
            case generationJobs = "generation_jobs"
            case profileName = "profile_name"
            case profilePath = "profile_path"
            case profiles
            case textProfile = "text_profile"
            case textProfiles = "text_profiles"
            case textProfilePath = "text_profile_path"
            case activeRequest = "active_request"
            case queue
            case playbackState = "playback_state"
            case status
            case speechBackend = "speech_backend"
            case clearedCount = "cleared_count"
            case cancelledRequestID = "cancelled_request_id"
        }

        public init(
            id: String,
            generatedFile: GeneratedFile? = nil,
            generatedFiles: [GeneratedFile]? = nil,
            generatedBatch: GeneratedBatch? = nil,
            generatedBatches: [GeneratedBatch]? = nil,
            generationJob: GenerationJob? = nil,
            generationJobs: [GenerationJob]? = nil,
            profileName: String? = nil,
            profilePath: String? = nil,
            profiles: [ProfileSummary]? = nil,
            textProfile: TextForSpeech.Profile? = nil,
            textProfiles: [TextForSpeech.Profile]? = nil,
            textProfilePath: String? = nil,
            activeRequest: ActiveRequest? = nil,
            queue: [QueuedRequest]? = nil,
            playbackState: PlaybackStateSnapshot? = nil,
            status: StatusEvent? = nil,
            speechBackend: SpeechBackend? = nil,
            clearedCount: Int? = nil,
            cancelledRequestID: String? = nil
        ) {
            self.id = id
            self.generatedFile = generatedFile
            self.generatedFiles = generatedFiles
            self.generatedBatch = generatedBatch
            self.generatedBatches = generatedBatches
            self.generationJob = generationJob
            self.generationJobs = generationJobs
            self.profileName = profileName
            self.profilePath = profilePath
            self.profiles = profiles
            self.textProfile = textProfile
            self.textProfiles = textProfiles
            self.textProfilePath = textProfilePath
            self.activeRequest = activeRequest
            self.queue = queue
            self.playbackState = playbackState
            self.status = status
            self.speechBackend = speechBackend
            self.clearedCount = clearedCount
            self.cancelledRequestID = cancelledRequestID
        }
    }

    struct PlaybackStateSnapshot: Codable, Sendable, Equatable {
        public let state: PlaybackState
        public let activeRequest: ActiveRequest?

        enum CodingKeys: String, CodingKey {
            case state
            case activeRequest = "active_request"
        }

        public init(state: PlaybackState, activeRequest: ActiveRequest?) {
            self.state = state
            self.activeRequest = activeRequest
        }
    }

    struct ActiveRequest: Codable, Sendable, Equatable {
        public let id: String
        public let op: String
        public let profileName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case profileName = "profile_name"
        }

        public init(id: String, op: String, profileName: String?) {
            self.id = id
            self.op = op
            self.profileName = profileName
        }
    }

    struct QueuedRequest: Codable, Sendable, Equatable {
        public let id: String
        public let op: String
        public let profileName: String?
        public let queuePosition: Int

        enum CodingKeys: String, CodingKey {
            case id
            case op
            case profileName = "profile_name"
            case queuePosition = "queue_position"
        }

        public init(id: String, op: String, profileName: String?, queuePosition: Int) {
            self.id = id
            self.op = op
            self.profileName = profileName
            self.queuePosition = queuePosition
        }
    }

    struct Failure: Encodable, Sendable, Equatable {
        public let id: String
        public let ok = false
        public let code: ErrorCode
        public let message: String

        public init(id: String, code: ErrorCode, message: String) {
            self.id = id
            self.code = code
            self.message = message
        }
    }

    enum ErrorCode: String, Codable, Sendable {
        case invalidJSON = "invalid_json"
        case invalidRequest = "invalid_request"
        case unknownOperation = "unknown_operation"
        case generatedFileNotFound = "generated_file_not_found"
        case generatedBatchNotFound = "generated_batch_not_found"
        case generatedFileAlreadyExists = "generated_file_already_exists"
        case generationJobNotFound = "generation_job_not_found"
        case generationJobAlreadyExists = "generation_job_already_exists"
        case generationJobNotExpirable = "generation_job_not_expirable"
        case profileNotFound = "profile_not_found"
        case profileAlreadyExists = "profile_already_exists"
        case invalidProfileName = "invalid_profile_name"
        case modelLoading = "model_loading"
        case modelGenerationFailed = "model_generation_failed"
        case requestCancelled = "request_cancelled"
        case workerShuttingDown = "worker_shutting_down"
        case audioPlaybackTimeout = "audio_playback_timeout"
        case audioPlaybackFailed = "audio_playback_failed"
        case requestNotFound = "request_not_found"
        case filesystemError = "filesystem_error"
        case internalError = "internal_error"
    }

    struct Error: Swift.Error, Sendable, Equatable {
        public let code: ErrorCode
        public let message: String

        public init(code: ErrorCode, message: String) {
            self.code = code
            self.message = message
        }
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension TextForSpeech.Context {
    var nilIfEmpty: TextForSpeech.Context? {
        cwd == nil && repoRoot == nil && textFormat == nil && nestedSourceFormat == nil ? nil : self
    }
}
