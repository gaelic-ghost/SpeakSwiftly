import Foundation

extension WorkerRequest {
    static func decode(from line: String, decoder: JSONDecoder = JSONDecoder()) throws -> WorkerRequest {
        let data = Data(line.utf8)
        let raw: RawWorkerRequest

        do {
            raw = try decoder.decode(RawWorkerRequest.self, from: data)
        } catch let error as DecodingError {
            throw WorkerError(
                code: .invalidRequest,
                message: "The request line contains an invalid field value or shape. \(describeDecodingError(error))",
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
            case "generate_speech":
                let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
                let resolved = try RawWorkerRequest.resolveSpeechTextInput(
                    id: id,
                    text: raw.text,
                    textProfileName: raw.textProfileName,
                    cwd: raw.cwd,
                    repoRoot: raw.repoRoot,
                    textFormat: raw.textFormat,
                    nestedSourceFormat: raw.nestedSourceFormat,
                    sourceFormat: raw.sourceFormat,
                )
                return .queueSpeech(
                    id: id,
                    text: resolved.text,
                    profileName: profileName,
                    textProfileName: resolved.textProfileName,
                    jobType: .live,
                    textContext: resolved.textContext,
                    sourceFormat: resolved.sourceFormat,
                )

            case "generate_audio_file":
                let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
                let resolved = try RawWorkerRequest.resolveSpeechTextInput(
                    id: id,
                    text: raw.text,
                    textProfileName: raw.textProfileName,
                    cwd: raw.cwd,
                    repoRoot: raw.repoRoot,
                    textFormat: raw.textFormat,
                    nestedSourceFormat: raw.nestedSourceFormat,
                    sourceFormat: raw.sourceFormat,
                )
                return .queueSpeech(
                    id: id,
                    text: resolved.text,
                    profileName: profileName,
                    textProfileName: resolved.textProfileName,
                    jobType: .file,
                    textContext: resolved.textContext,
                    sourceFormat: resolved.sourceFormat,
                )

            case "generate_batch":
                let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
                let items = try RawWorkerRequest.resolveBatchItems(id: id, rawItems: raw.items)
                return .queueBatch(id: id, profileName: profileName, items: items)

            case "get_generated_file":
                let artifactID = try requireNonEmpty(raw.artifactID, field: "artifact_id", id: id)
                return .generatedFile(id: id, artifactID: artifactID)

            case "list_generated_files":
                return .generatedFiles(id: id)

            case "get_generated_batch":
                let batchID = try requireNonEmpty(raw.batchID ?? raw.jobID, field: "batch_id", id: id)
                return .generatedBatch(id: id, batchID: batchID)

            case "list_generated_batches":
                return .generatedBatches(id: id)

            case "expire_generation_job":
                let jobID = try requireNonEmpty(raw.jobID, field: "job_id", id: id)
                return .expireGenerationJob(id: id, jobID: jobID)

            case "get_generation_job":
                let jobID = try requireNonEmpty(raw.jobID, field: "job_id", id: id)
                return .generationJob(id: id, jobID: jobID)

            case "list_generation_jobs":
                return .generationJobs(id: id)

            case "create_voice_profile_from_description":
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
                    cwd: raw.cwd?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                )

            case "create_voice_profile_from_audio":
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
                    cwd: raw.cwd?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                )

            case "list_voice_profiles":
                return .listProfiles(id: id)

            case "update_voice_profile_name":
                let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
                let newProfileName = try requireNonEmpty(raw.newProfileName, field: "new_profile_name", id: id)
                return .renameProfile(id: id, profileName: profileName, newProfileName: newProfileName)

            case "reroll_voice_profile":
                let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
                return .rerollProfile(id: id, profileName: profileName)

            case "delete_voice_profile":
                let profileName = try requireNonEmpty(raw.profileName, field: "profile_name", id: id)
                return .removeProfile(id: id, profileName: profileName)

            case "get_active_text_profile":
                return .textProfileActive(id: id)

            case "get_text_profile":
                let textProfileName = try requireNonEmpty(raw.textProfileName, field: "text_profile_name", id: id)
                return .textProfile(id: id, name: textProfileName)

            case "list_text_profiles":
                return .textProfiles(id: id)

            case "get_text_profile_style":
                return .textProfileStyle(id: id)

            case "get_effective_text_profile":
                let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                return .textProfileEffective(id: id, name: textProfileName)

            case "get_text_profile_persistence":
                return .textProfilePersistence(id: id)

            case "load_text_profiles":
                return .loadTextProfiles(id: id)

            case "save_text_profiles":
                return .saveTextProfiles(id: id)

            case "set_text_profile_style":
                let style = try require(raw.textProfileStyle, field: "text_profile_style", id: id)
                return .setTextProfileStyle(id: id, style: style)

            case "create_text_profile":
                let textProfileID = try requireNonEmpty(raw.textProfileID, field: "text_profile_id", id: id)
                let textProfileDisplayName = try requireNonEmpty(
                    raw.textProfileDisplayName,
                    field: "text_profile_display_name",
                    id: id,
                )
                return .createTextProfile(
                    id: id,
                    profileID: textProfileID,
                    profileName: textProfileDisplayName,
                    replacements: raw.replacements ?? [],
                )

            case "replace_text_profile":
                guard let textProfile = raw.textProfile else {
                    throw WorkerError(
                        code: .invalidRequest,
                        message: "Request '\(id)' is missing a 'text_profile' object.",
                    )
                }

                return .storeTextProfile(id: id, profile: textProfile)

            case "replace_active_text_profile":
                guard let textProfile = raw.textProfile else {
                    throw WorkerError(
                        code: .invalidRequest,
                        message: "Request '\(id)' is missing a 'text_profile' object.",
                    )
                }

                return .useTextProfile(id: id, profile: textProfile)

            case "delete_text_profile":
                let textProfileName = try requireNonEmpty(raw.textProfileName, field: "text_profile_name", id: id)
                return .removeTextProfile(id: id, profileName: textProfileName)

            case "reset_text_profile":
                return .resetTextProfile(id: id)

            case "list_text_replacements":
                let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                return .textReplacements(id: id, profileName: textProfileName)

            case "create_text_replacement":
                guard let replacement = raw.replacement else {
                    throw WorkerError(
                        code: .invalidRequest,
                        message: "Request '\(id)' is missing a 'replacement' object.",
                    )
                }

                let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                return .addTextReplacement(id: id, replacement: replacement, profileName: textProfileName)

            case "replace_text_replacement":
                guard let replacement = raw.replacement else {
                    throw WorkerError(
                        code: .invalidRequest,
                        message: "Request '\(id)' is missing a 'replacement' object.",
                    )
                }

                let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                return .replaceTextReplacement(id: id, replacement: replacement, profileName: textProfileName)

            case "delete_text_replacement":
                let replacementID = try requireNonEmpty(raw.replacementID, field: "replacement_id", id: id)
                let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                return .removeTextReplacement(id: id, replacementID: replacementID, profileName: textProfileName)

            case "clear_text_replacements":
                let textProfileName = raw.textProfileName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                return .clearTextReplacements(id: id, profileName: textProfileName)

            case "list_generation_queue":
                return .listQueue(id: id, queueType: .generation)

            case "list_playback_queue":
                return .listQueue(id: id, queueType: .playback)

            case "get_status":
                return .status(id: id)

            case "get_runtime_overview":
                return .overview(id: id)

            case "set_speech_backend":
                let speechBackend = try require(raw.speechBackend, field: "speech_backend", id: id)
                return .switchSpeechBackend(id: id, speechBackend: speechBackend)

            case "reload_models":
                return .reloadModels(id: id)

            case "unload_models":
                return .unloadModels(id: id)

            case "playback_pause":
                return .playback(id: id, action: .pause)

            case "playback_resume":
                return .playback(id: id, action: .resume)

            case "get_playback_state":
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
            case let .dataCorrupted(context):
                context.debugDescription
            case let .keyNotFound(key, context):
                "Missing key '\(key.stringValue)'. \(context.debugDescription)"
            case let .typeMismatch(_, context), let .valueNotFound(_, context):
                context.debugDescription
            @unknown default:
                "The request payload could not be decoded."
        }
    }
}
