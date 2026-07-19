import Foundation

enum WorkerRequest: Equatable {
    case queueSpeech(
        id: String,
        text: String,
        profileName: String,
        textProfileID: String?,
        jobType: SpeechJobType,
        audioFormat: SpeakSwiftly.GeneratedAudioFileFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool?,
    )
    case queueBatch(
        id: String,
        profileName: String,
        items: [SpeakSwiftly.GenerationJobItem],
    )
    case replayRecentAudio(
        id: String,
        recentAudioID: String,
        text: String,
        profileName: String,
        requestContext: SpeakSwiftly.RequestContext?,
    )
    case recentGeneratedAudio(id: String)
    case recentGeneratedAudioChunks(id: String, recentAudioID: String)
    case replayRecentAudioAll(
        id: String,
        replayMode: SpeakSwiftly.RecentGeneratedAudioReplayMode,
        requestContext: SpeakSwiftly.RequestContext?,
    )
    case clearRecentGeneratedAudio(id: String)
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
        author: SpeakSwiftly.ProfileAuthor,
        seed: SpeakSwiftly.ProfileSeed?,
        outputPath: String?,
        cwd: String?,
    )
    case createClone(
        id: String,
        profileName: String,
        referenceAudioPath: String,
        vibe: SpeakSwiftly.Vibe,
        transcript: String?,
        cwd: String?,
    )
    case listProfiles(id: String)
    case renameProfile(id: String, profileName: String, newProfileName: String)
    case rerollProfile(id: String, profileName: String)
    case removeProfile(id: String, profileName: String)
    case textProfileActive(id: String)
    case textProfile(id: String, profileID: String)
    case textProfiles(id: String)
    case activeTextProfileStyle(id: String)
    case textProfileStyleOptions(id: String)
    case textProfileEffective(id: String)
    case textProfilePersistence(id: String)
    case loadTextProfiles(id: String)
    case saveTextProfiles(id: String)
    case setActiveTextProfileStyle(id: String, style: SpeakSwiftly.TextProfileStyle)
    case createTextProfile(id: String, profileName: String)
    case renameTextProfile(id: String, profileID: String, profileName: String)
    case setActiveTextProfile(id: String, profileID: String)
    case deleteTextProfile(id: String, profileID: String)
    case factoryResetTextProfiles(id: String)
    case resetTextProfile(id: String, profileID: String)
    case addTextReplacement(id: String, replacement: SpeakSwiftly.TextReplacement, profileID: String?)
    case replaceTextReplacement(id: String, replacement: SpeakSwiftly.TextReplacement, profileID: String?)
    case removeTextReplacement(id: String, replacementID: String, profileID: String?)
    case listQueue(id: String, queueType: WorkerQueueType)
    case status(id: String)
    case overview(id: String)
    case defaultVoiceProfile(id: String)
    case setDefaultVoiceProfile(id: String, profileName: String)
    case switchSpeechBackend(id: String, speechBackend: SpeakSwiftly.SpeechBackend)
    case reloadModels(id: String)
    case unloadModels(id: String)
    case playback(id: String, action: PlaybackAction)
    case clearQueue(id: String, queueType: WorkerQueueType?)
    case cancelRequest(id: String, requestID: String, queueType: WorkerQueueType?)

    struct ExecutionPolicy: Equatable {
        var isImmediateControlOperation = false
        var acknowledgesEnqueueImmediately = false
        var emitsTerminalSuccessAfterAcknowledgement = false
        var requiresResidentModels = false
        var requiresPlayback = false
        var mutatesResidentState = false
        var requiresPlaybackDrainBeforeStart = false
    }

    static let runtimeDefaultVoiceProfilePlaceholder = "__speakswiftly_runtime_default_voice_profile__"

    var id: String {
        switch self {
            case .queueSpeech(id: let id, text: _, profileName: _, textProfileID: _, jobType: _, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _),
                 .queueBatch(id: let id, profileName: _, items: _),
                 .replayRecentAudio(id: let id, recentAudioID: _, text: _, profileName: _, requestContext: _),
                 let .recentGeneratedAudio(id),
                 let .recentGeneratedAudioChunks(id, _),
                 let .replayRecentAudioAll(id, _, _),
                 let .clearRecentGeneratedAudio(id),
                 let .generatedFile(id, _),
                 let .generatedFiles(id),
                 let .generatedBatch(id, _),
                 let .generatedBatches(id),
                 let .expireGenerationJob(id, _),
                 let .generationJob(id, _),
                 let .generationJobs(id),
                 let .createProfile(id, _, _, _, _, _, _, _, _),
                 let .createClone(id, _, _, _, _, _),
                 let .listProfiles(id),
                 let .renameProfile(id, _, _),
                 let .rerollProfile(id, _),
                 let .removeProfile(id, _),
                 let .textProfileActive(id),
                 let .textProfile(id, _),
                 let .textProfiles(id),
                 let .activeTextProfileStyle(id),
                 let .textProfileStyleOptions(id),
                 let .textProfileEffective(id),
                 let .textProfilePersistence(id),
                 let .loadTextProfiles(id),
                 let .saveTextProfiles(id),
                 let .setActiveTextProfileStyle(id, _),
                 let .createTextProfile(id, _),
                 let .renameTextProfile(id, _, _),
                 let .setActiveTextProfile(id, _),
                 let .deleteTextProfile(id, _),
                 let .factoryResetTextProfiles(id),
                 let .resetTextProfile(id, _),
                 let .addTextReplacement(id, _, _),
                 let .replaceTextReplacement(id, _, _),
                 let .removeTextReplacement(id, _, _),
                 let .listQueue(id, _),
                 let .status(id),
                 let .overview(id),
                 let .defaultVoiceProfile(id),
                 let .setDefaultVoiceProfile(id, _),
                 let .switchSpeechBackend(id, _),
                 let .reloadModels(id),
                 let .unloadModels(id),
                 let .playback(id, _),
                 let .clearQueue(id, _),
                 let .cancelRequest(id, _, _):
                id
        }
    }

    var opName: String {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .live, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _):
                "generate_speech"
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .stream, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _):
                "generate_audio_stream"
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .file, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _):
                "generate_audio_file"
            case .queueBatch:
                "generate_batch"
            case .replayRecentAudio:
                "replay_recent_audio"
            case .recentGeneratedAudio:
                "list_recent_generated_audio"
            case .recentGeneratedAudioChunks:
                "get_recent_generated_audio_chunks"
            case .replayRecentAudioAll:
                "replay_recent_audio_all"
            case .clearRecentGeneratedAudio:
                "clear_recent_generated_audio"
            case .generatedFile:
                "get_generated_file"
            case .generatedFiles:
                "list_generated_files"
            case .generatedBatch:
                "get_generated_batch"
            case .generatedBatches:
                "list_generated_batches"
            case .expireGenerationJob:
                "expire_generation_job"
            case .generationJob:
                "get_generation_job"
            case .generationJobs:
                "list_generation_jobs"
            case let .createProfile(id: _, profileName: _, text: _, vibe: _, voiceDescription: _, author: author, seed: _, outputPath: _, cwd: _):
                switch author {
                    case .user:
                        "create_voice_profile_from_description"
                    case .system:
                        "upsert_system_voice_profile_from_description"
                }
            case .createClone:
                "create_voice_profile_from_audio"
            case .listProfiles:
                "list_voice_profiles"
            case .renameProfile:
                "update_voice_profile_name"
            case .rerollProfile:
                "reroll_voice_profile"
            case .removeProfile:
                "delete_voice_profile"
            case .textProfileActive:
                "get_active_text_profile"
            case .textProfile:
                "get_text_profile"
            case .textProfiles:
                "list_text_profiles"
            case .activeTextProfileStyle:
                "get_active_text_profile_style"
            case .textProfileStyleOptions:
                "list_text_profile_styles"
            case .textProfileEffective:
                "get_effective_text_profile"
            case .textProfilePersistence:
                "get_text_profile_persistence"
            case .loadTextProfiles:
                "load_text_profiles"
            case .saveTextProfiles:
                "save_text_profiles"
            case .setActiveTextProfileStyle:
                "set_active_text_profile_style"
            case .createTextProfile:
                "create_text_profile"
            case .renameTextProfile:
                "update_text_profile_name"
            case .setActiveTextProfile:
                "set_active_text_profile"
            case .deleteTextProfile:
                "delete_text_profile"
            case .factoryResetTextProfiles:
                "factory_reset_text_profiles"
            case .resetTextProfile:
                "reset_text_profile"
            case .addTextReplacement:
                "create_text_replacement"
            case .replaceTextReplacement:
                "replace_text_replacement"
            case .removeTextReplacement:
                "delete_text_replacement"
            case .listQueue(_, .generation):
                "list_generation_queue"
            case .listQueue(_, .playback):
                "list_playback_queue"
            case .status:
                "get_status"
            case .overview:
                "get_runtime_overview"
            case .defaultVoiceProfile:
                "get_default_voice_profile"
            case .setDefaultVoiceProfile:
                "set_default_voice_profile"
            case .switchSpeechBackend:
                "set_speech_backend"
            case .reloadModels:
                "reload_models"
            case .unloadModels:
                "unload_models"
            case .playback(_, .pause):
                "playback_pause"
            case .playback(_, .resume):
                "playback_resume"
            case .playback(_, .state):
                "get_playback_state"
            case .clearQueue(_, nil):
                "clear_queue"
            case .clearQueue(_, .generation):
                "clear_generation_queue"
            case .clearQueue(_, .playback):
                "clear_playback_queue"
            case .cancelRequest(_, _, nil):
                "cancel_request"
            case .cancelRequest(_, _, .generation):
                "cancel_generation"
            case .cancelRequest(_, _, .playback):
                "cancel_playback"
        }
    }

    var requestKind: SpeakSwiftly.RequestKind {
        SpeakSwiftly.RequestKind(rawValue: opName)
    }

    var isSpeechRequest: Bool {
        switch self {
            case .queueSpeech, .queueBatch:
                true
            default:
                false
        }
    }

    var requiresResidentModels: Bool {
        executionPolicy.requiresResidentModels
    }

    var mutatesResidentState: Bool {
        executionPolicy.mutatesResidentState
    }

    var requiresPlayback: Bool {
        executionPolicy.requiresPlayback
    }

    var acknowledgesEnqueueImmediately: Bool {
        executionPolicy.acknowledgesEnqueueImmediately
    }

    var emitsTerminalSuccessAfterAcknowledgement: Bool {
        executionPolicy.emitsTerminalSuccessAfterAcknowledgement
    }

    var isImmediateControlOperation: Bool {
        executionPolicy.isImmediateControlOperation
    }

    var executionPolicy: ExecutionPolicy {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .live, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _):
                ExecutionPolicy(
                    acknowledgesEnqueueImmediately: true,
                    requiresResidentModels: true,
                    requiresPlayback: true,
                )
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .stream, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _),
                 .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: .file, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _),
                 .queueBatch:
                ExecutionPolicy(
                    acknowledgesEnqueueImmediately: true,
                    emitsTerminalSuccessAfterAcknowledgement: true,
                    requiresResidentModels: true,
                )
            case .replayRecentAudio:
                ExecutionPolicy(acknowledgesEnqueueImmediately: true)
            case .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels:
                ExecutionPolicy(
                    acknowledgesEnqueueImmediately: true,
                    emitsTerminalSuccessAfterAcknowledgement: true,
                    mutatesResidentState: true,
                    requiresPlaybackDrainBeforeStart: true,
                )
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .recentGeneratedAudio,
                 .recentGeneratedAudioChunks,
                 .replayRecentAudioAll,
                 .clearRecentGeneratedAudio,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .textProfileActive,
                 .textProfile,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .renameTextProfile,
                 .setActiveTextProfile,
                 .deleteTextProfile,
                 .factoryResetTextProfiles,
                 .resetTextProfile,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .listQueue,
                 .status,
                 .overview,
                 .defaultVoiceProfile,
                 .setDefaultVoiceProfile,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                ExecutionPolicy(isImmediateControlOperation: true)
            default:
                ExecutionPolicy()
        }
    }

    var requiresPlaybackDrainBeforeStart: Bool {
        executionPolicy.requiresPlaybackDrainBeforeStart
    }

    var formsOrderedControlBarrier: Bool {
        mutatesResidentState
    }

    var canBypassParkedResidentWork: Bool {
        mutatesResidentState
    }

    var voiceProfile: String? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: let profileName, textProfileID: _, jobType: _, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _),
                 .replayRecentAudio(id: _, recentAudioID: _, text: _, profileName: let profileName, requestContext: _),
                 .queueBatch(id: _, profileName: let profileName, items: _),
                 let .createProfile(_, profileName, _, _, _, _, _, _, _),
                 let .createClone(_, profileName, _, _, _, _),
                 let .renameProfile(_, profileName, _),
                 let .rerollProfile(_, profileName),
                 let .removeProfile(_, profileName):
                profileName
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .recentGeneratedAudio,
                 .recentGeneratedAudioChunks,
                 .replayRecentAudioAll,
                 .clearRecentGeneratedAudio,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .textProfileActive,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .factoryResetTextProfiles,
                 .listProfiles,
                 .listQueue,
                 .status,
                 .overview,
                 .defaultVoiceProfile,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                nil
            case let .setDefaultVoiceProfile(_, profileName):
                profileName
            case let .renameTextProfile(_, _, profileName):
                profileName
            case .textProfile,
                 .textProfileEffective,
                 .setActiveTextProfile,
                 .deleteTextProfile,
                 .resetTextProfile,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement:
                nil
        }
    }

    var textProfileID: String? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: let textProfileID, jobType: _, audioFormat: _, requestContext: _, qwenPreModelTextChunking: _):
                return textProfileID
            case .queueBatch(id: _, profileName: _, items: let items):
                let ids = Set(items.compactMap(\.textProfile))
                return ids.count == 1 ? ids.first : nil
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .recentGeneratedAudio,
                 .recentGeneratedAudioChunks,
                 .replayRecentAudioAll,
                 .clearRecentGeneratedAudio,
                 .replayRecentAudio,
                 .createProfile,
                 .createClone,
                 .listProfiles,
                 .renameProfile,
                 .rerollProfile,
                 .removeProfile,
                 .textProfileActive,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .factoryResetTextProfiles,
                 .listQueue,
                 .status,
                 .overview,
                 .defaultVoiceProfile,
                 .setDefaultVoiceProfile,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                return nil
            case let .textProfile(_, profileID),
                 let .renameTextProfile(_, profileID, _),
                 let .setActiveTextProfile(_, profileID),
                 let .deleteTextProfile(_, profileID),
                 let .resetTextProfile(_, profileID):
                return profileID
            case let .addTextReplacement(_, _, profileID),
                 let .replaceTextReplacement(_, _, profileID),
                 let .removeTextReplacement(_, _, profileID):
                return profileID
            case .textProfileEffective:
                return nil
        }
    }

    var requestContext: SpeakSwiftly.RequestContext? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: _, audioFormat: _, requestContext: let requestContext, qwenPreModelTextChunking: _):
                requestContext
            case .replayRecentAudio(id: _, recentAudioID: _, text: _, profileName: _, requestContext: let requestContext):
                requestContext
            case .replayRecentAudioAll(id: _, replayMode: _, requestContext: let requestContext):
                requestContext
            case .queueBatch:
                nil
            case .generatedFile,
                 .generatedFiles,
                 .generatedBatch,
                 .generatedBatches,
                 .recentGeneratedAudio,
                 .recentGeneratedAudioChunks,
                 .clearRecentGeneratedAudio,
                 .expireGenerationJob,
                 .generationJob,
                 .generationJobs,
                 .createProfile,
                 .createClone,
                 .listProfiles,
                 .renameProfile,
                 .rerollProfile,
                 .removeProfile,
                 .textProfileActive,
                 .textProfile,
                 .textProfiles,
                 .activeTextProfileStyle,
                 .textProfileStyleOptions,
                 .textProfileEffective,
                 .textProfilePersistence,
                 .loadTextProfiles,
                 .saveTextProfiles,
                 .setActiveTextProfileStyle,
                 .createTextProfile,
                 .addTextReplacement,
                 .replaceTextReplacement,
                 .removeTextReplacement,
                 .renameTextProfile,
                 .setActiveTextProfile,
                 .deleteTextProfile,
                 .factoryResetTextProfiles,
                 .resetTextProfile,
                 .listQueue,
                 .status,
                 .overview,
                 .defaultVoiceProfile,
                 .setDefaultVoiceProfile,
                 .switchSpeechBackend,
                 .reloadModels,
                 .unloadModels,
                 .playback,
                 .clearQueue,
                 .cancelRequest:
                nil
        }
    }

    var qwenPreModelTextChunking: Bool? {
        switch self {
            case .queueSpeech(id: _, text: _, profileName: _, textProfileID: _, jobType: _, audioFormat: _, requestContext: _, qwenPreModelTextChunking: let qwenPreModelTextChunking):
                qwenPreModelTextChunking
            default:
                nil
        }
    }

    func resolvingRuntimeDefaultVoiceProfile(_ defaultVoiceProfileName: String) -> WorkerRequest {
        switch self {
            case let .queueSpeech(id, text, profileName, textProfileID, jobType, audioFormat, requestContext, qwenPreModelTextChunking):
                .queueSpeech(
                    id: id,
                    text: text,
                    profileName: profileName == Self.runtimeDefaultVoiceProfilePlaceholder ? defaultVoiceProfileName : profileName,
                    textProfileID: textProfileID,
                    jobType: jobType,
                    audioFormat: audioFormat,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking,
                )
            case let .queueBatch(id, profileName, items):
                .queueBatch(
                    id: id,
                    profileName: profileName == Self.runtimeDefaultVoiceProfilePlaceholder ? defaultVoiceProfileName : profileName,
                    items: items,
                )
            case let .replayRecentAudio(id, recentAudioID, text, profileName, requestContext):
                .replayRecentAudio(
                    id: id,
                    recentAudioID: recentAudioID,
                    text: text,
                    profileName: profileName == Self.runtimeDefaultVoiceProfilePlaceholder ? defaultVoiceProfileName : profileName,
                    requestContext: requestContext,
                )
            default:
                self
        }
    }
}
